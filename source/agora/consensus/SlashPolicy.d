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

    /***************************************************************************

        Constructor

        Params:
            enroll_man = the EnrollmentManager
            params = the consensus-critical constants

    ***************************************************************************/

    public this (immutable(ConsensusParams) params)
    {
        this.penalty_amount = Amount(10_000L * 10_000_000L);
        this.penalty_address = params.CommonsBudgetAddress;
    }

    /***************************************************************************

        HHHHHH

        Params:
            HHHHHH

    ***************************************************************************/

    public bool checkInvalidValidator (Height height, Height enrolled,
        ushort last_distance) @safe nothrow
    {
        scope(failure) assert(0);
        assert(height >= enrolled);
        ushort curr_distance = cast(ushort)(height - enrolled);
        if (last_distance >= curr_distance)
            return true;
        else
            return false;
    }

    /***************************************************************************

        HHHHHH

        Params:
            height = current block height
            finder = the delegate to find UTXOs with

        Returns:
            HHHHHH

    ***************************************************************************/

    public Transaction[] createSlashingTransactions (Hash[] slashed_utxos,
        scope UTXOFinder finder)@safe
    {
        Transaction[] txs;
        if (slashed_utxos.length > 0)
        {
            log.warn("There are some validators that have not revealed " ~
                "pre-images timely. UTXOs{} will be slashed", slashed_utxos);
        }

        foreach (utxo; slashed_utxos)
        {
            UTXO utxo_value;
            if (finder(utxo, utxo_value))
            {
                auto refund_value = Amount(utxo_value.output.value);
                refund_value.sub(this.penalty_amount);
                txs ~= Transaction(TxType.Payment,
                    [Input(utxo)],
                    [Output(this.penalty_amount, this.penalty_address),
                        Output(refund_value, utxo_value.output.address)]);
            }
            else
            {
                log.fatal("No UTXO value for a uxto hash {}", utxo);
            }
        }

        return txs;
    }
}
