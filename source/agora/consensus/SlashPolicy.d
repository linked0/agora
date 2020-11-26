/*******************************************************************************

    Manages the slashing policy for the misbehaving validators that do not
    publish pre-images timely.

    HHHHHH Manages ...

    This class currently has two responsibilities:
    - It determines when the misbehaving validators will be slashed -- in other
        words, how many times of missing pre-images it will allow.
    - It determines what the penalty is for misbehaving validators -- in other
        words, how many BOA it should pay for a penalty.

    All the validators should publish their pre-images timely in order for
    the network to maintain randomness. So we need a penalty as an incentive
    to make validators publish them regularly. So this class manages all the
    policies for penalty and slashing.
    See https://github.com/bpfkorea/agora/issues/1076.

    Copyright:
        Copyright (c) 2020 BOS Platform Foundation Korea
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.consensus.SlashPolicy;

import agora.common.Amount;
import agora.common.crypto.Key;
import agora.common.Types;
import agora.consensus.EnrollmentManager;
import agora.consensus.data.Params;
import agora.consensus.data.Enrollment;
import agora.consensus.data.Params;
import agora.consensus.data.PreImageInfo;
import agora.consensus.data.Transaction;
import agora.consensus.state.UTXODB;
import agora.utils.Log;
version (unittest) import agora.utils.Test;

import std.exception;

mixin AddLogger!();

/*******************************************************************************

    Manage the policy for slashing

*******************************************************************************/

public class SlashPolicy
{
    // The amount of the penalty set to 10K BOA
    public immutable Amount penalty_amount;

    // The address to get a penalty
    public immutable PublicKey penalty_address;

    // Enrollment manager
    private EnrollmentManager enroll_man;

    /***************************************************************************

        Constructor

        Params:
            enroll_man = the EnrollmentManager
            params = the consensus-critical constants

    ***************************************************************************/

    public this (EnrollmentManager enroll_man, immutable(ConsensusParams) params)
    {
        this.enroll_man = enroll_man;
        this.penalty_amount = Amount(10_000L * 10_000_000L);
        this.penalty_address = params.CommonsBudgetAddress;
    }

    /***************************************************************************

        HHHHHH

        Params:
            missing_validators = HHHHHH
            height = the desired block height to look up the validators for

    ***************************************************************************/

    public void getMissingValidators (Height height,
        ref uint[] missing_validators) @safe
    {
        Hash[] keys;
        if (!this.enroll_man.getEnrolledUTXOs(keys) || keys.length == 0)
        {
            log.fatal("Could not retrieve enrollments / no enrollments found");
            assert(0);
        }

        foreach (idx, utxo_key; keys)
        {
            if (!checkValidValidator(height, utxo_key))
            {
                missing_validators ~= cast(uint)idx;
            }
        }
    }

    /***************************************************************************

        HHHHHH

        Params:
            height = the desired block height to look up the images for

        Returns:
            HHHHHH

    ***************************************************************************/

    public Hash getPreimageRoot (in Height height) @safe nothrow
    {
        Hash[] keys;
        if (!this.enroll_man.getEnrolledUTXOs(keys) || keys.length == 0)
        {
            log.fatal("Could not retrieve enrollments / no enrollments found");
            assert(0);
        }

        Hash[] valid_keys;
        foreach (key; keys)
        {
            if (checkValidValidator(height, key))
                valid_keys ~= key;
        }

        return this.enroll_man.getRandomSeed(valid_keys, height);
    }

    /***************************************************************************

        XXXXXX

        Params:
            XXXXXX

    ***************************************************************************/

    private bool checkValidValidator (in Height height, in Hash utxo_key)
        @safe nothrow
    {
        auto preimage = this.enroll_man.getValidatorPreimage(utxo_key);
        auto enrolled = this.enroll_man.getEnrolledHeight(preimage.enroll_key);
        assert(height >= enrolled);
        if (preimage.distance >= cast(ushort)(height - enrolled - 1))
            return true;
        else
            return false;
    }
}

// Test for getting the candidates to be slashed due to missing pre-images
unittest
{
    import agora.common.crypto.Schnorr;
    import agora.common.Hash;
    import agora.consensus.data.Transaction;
    import agora.consensus.PreImage;
    import agora.consensus.state.UTXOSet;

    import std.algorithm;
    import std.range;

    scope utxo_set = new TestUTXOSet;
    Hash[] utxo_hashes;

    // genesisSpendable returns 8 outputs
    auto pairs = iota(8).map!(idx => WK.Keys[idx]).array;
    auto txs = genesisSpendable()
        .enumerate
        .map!(tup => tup.value
            .refund(pairs[tup.index].address)
            .sign(TxType.Freeze))
        .each!((tx) {
            utxo_set.put(tx);
            utxo_hashes ~= UTXO.getHash(tx.hashFull(), 0);
        });

    auto params = new immutable(ConsensusParams);
    scope enroll_man = new EnrollmentManager(":memory:", WK.Keys.A, params);

    // create 8 enrollments
    Enrollment[] enrollments;
    PreImageCache[] caches;
    foreach (idx, kp; pairs)
    {
        auto pair = Pair.fromScalar(secretKeyToCurveScalar(kp.secret));
        auto cycle = PreImageCycle(
                0, 0,
                PreImageCache(PreImageCycle.NumberOfCycles, params.ValidatorCycle),
                PreImageCache(params.ValidatorCycle, 1));
        const seed = cycle.populate(pair.v, true);
        caches ~= cycle.preimages;
        auto enroll = EnrollmentManager.makeEnrollment(
            pair, utxo_hashes[idx], params.ValidatorCycle,
            seed, idx);
        assert(enroll_man.addEnrollment(enroll, kp.address, Height(1),
                &utxo_set.peekUTXO));
        enrollments ~= enroll;
    }

    // 8 validators(=enrollments) are enrolled at height of 1
    UTXO[Hash] self_utxos;
    self_utxos[utxo_hashes[0]] = utxo_set[utxo_hashes[0]];
    foreach (idx, enroll; enrollments)
        assert(enroll_man.addValidator(enroll, pairs[idx].address, Height(1),
            &utxo_set.peekUTXO, self_utxos) is null);
    assert(enroll_man.validatorCount() == 8);

    // a preimage exists as commitment of the enrollment
    scope slash_man = new SlashPolicy(enroll_man, params);
    uint[] missing_validators;
    slash_man.getMissingValidators(Height(2), missing_validators);
    assert(missing_validators.length == 0);

    // get all the validators and find index of the first and second validastors
    uint first_validator;
    uint second_validator;
    Hash[] utxos;
    assert(enroll_man.getEnrolledUTXOs(utxos));
    foreach (idx, utxo; utxos)
        if (utxo == enrollments[0].utxo_key)
        {
            first_validator = cast(uint)idx;
            break;
        }
    foreach (idx, utxo; utxos)
        if (utxo == enrollments[0].utxo_key)
        {
            second_validator = cast(uint)idx;
            break;
        }

    // the first validator reveals preimage
    PreImageInfo preimage_1 = PreImageInfo(
        enrollments[0].utxo_key,
        caches[0][$ - 2],
        1
    );
    assert(hashFull(preimage_1.hash) == enrollments[0].random_seed);
    enroll_man.addPreimage(preimage_1);
    auto gotten_image = enroll_man.getValidatorPreimage(enrollments[0].utxo_key);
    assert(preimage_1 == gotten_image);

    // the second validator reveals preimage
    PreImageInfo preimage_2 = PreImageInfo(
        enrollments[1].utxo_key,
        caches[1][$ - 2],
        1
    );
    assert(hashFull(preimage_2.hash) == enrollments[1].random_seed);
    enroll_man.addPreimage(preimage_2);
    gotten_image = enroll_man.getValidatorPreimage(enrollments[1].utxo_key);
    assert(preimage_2 == gotten_image);

    // check missing preimage
    slash_man.getMissingValidators(Height(3), missing_validators);
    assert(missing_validators.length == 6);
    assert(missing_validators.find(first_validator).empty());
    assert(missing_validators.find(second_validator).empty());

    // get and check preimage root
    Hash preimage_root = slash_man.getPreimageRoot(Height(3));
    assert(preimage_root ==
        hashMulti(hashMulti(Hash.init, preimage_1), preimage_2));
}
