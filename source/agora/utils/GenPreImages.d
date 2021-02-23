/*******************************************************************************

    Various utilities for testing purpose

    Utilities in this module can be used in test code.
    There are currently multiple testing approaches:
    - Unittests in the various `agora` module, the most common, cheapest,
      and a way to do white box testing;
    - Unittests under `agora.test`: Those unittests rely on the LocalRest
      library to simulate a network where nodes are thread who communicate
      via message passing.
    - Unit integration tests in `${ROOT}/tests/unit/` which are similar to
      unittests but provide a way to test IO-using code.
    - System integration tests: those are fully fledged tests that spawns
      unmodified, real nodes within Docker containers and act as a client.

    Any symbol in this module can be used by any of those method,
    which is why this module is neither restricted by `package(agora):`
    nor `version(unittest):`.

    Copyright:
        Copyright (c) 2020 BOS Platform Foundation Korea
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.utils.GenPreImages;

import agora.common.Amount;
import agora.common.crypto.Key;
import agora.common.Serializer;
import agora.common.Types;
import agora.consensus.data.Block;
import agora.consensus.data.DataPayload;
import agora.consensus.data.Transaction;
import agora.consensus.data.genesis.Test;
import agora.crypto.ECC;
import agora.crypto.Hash;
import agora.crypto.Schnorr;
import agora.script.Lock;
import agora.utils.Test;
public import agora.utils.Utility : retryFor;

import std.algorithm;
import std.array;
import std.file;
import std.format;
import std.functional;
import std.path;
import std.range;

import core.exception;
import core.time;

version (none)
unittest
{
    import std.stdio;
    import agora.common.crypto.Key;
    import agora.consensus.data.Enrollment;
    import agora.utils.PrettyPrinter;

    writeln("NODE2 secret: ", WK.Keys.NODE2.secret.prettify());
    writeln("NODE3 secret: ", WK.Keys.NODE3.secret.prettify());
    writeln("NODE4 secret: ", WK.Keys.NODE4.secret.prettify());
    writeln("NODE5 secret: ", WK.Keys.NODE5.secret.prettify());
    writeln("NODE6 secret: ", WK.Keys.NODE6.secret.prettify());
    writeln("NODE7 secret: ", WK.Keys.NODE7.secret.prettify());

    SecretKey[string] secrets;
    secrets["NODE6"] = WK.Keys.NODE6.secret;
    secrets["NODE3"] = WK.Keys.NODE3.secret;
    secrets["NODE2"] = WK.Keys.NODE2.secret;
    secrets["NODE4"] = WK.Keys.NODE4.secret;
    secrets["NODE7"] = WK.Keys.NODE7.secret;
    secrets["NODE5"] = WK.Keys.NODE5.secret;

    Hash[string] utxos;
    utxos["NODE6"] = GenesisBlock.header.enrollments[0].utxo_key;
    utxos["NODE3"] = GenesisBlock.header.enrollments[1].utxo_key;
    utxos["NODE2"] = GenesisBlock.header.enrollments[2].utxo_key;
    utxos["NODE4"] = GenesisBlock.header.enrollments[3].utxo_key;
    utxos["NODE7"] = GenesisBlock.header.enrollments[4].utxo_key;
    utxos["NODE5"] = GenesisBlock.header.enrollments[5].utxo_key;

    Pair[string] key_pairs;


    foreach (name, secret; secrets)
    {
        uint seek_nonce = 0;
        auto key_pair = Pair.fromScalar(secretKeyToCurveScalar(secret));
        key_pairs[name] = key_pair;
        const cycle_seed = hashMulti(
                    key_pair.v, "consensus.preimages", seek_nonce);
        auto count = 100;
        auto data = new Hash[](count);
        data[0] = cycle_seed;
        Hash seed = cycle_seed;
        Hash last_entry;
        foreach (ref entry; data[1 .. $])
        {
            foreach (idx; 0 .. 20)
                seed = hashFull(seed);
            entry = seed;
            last_entry = entry;
        }

        auto preimages = new Hash[](20);
        preimages[0] = data[$ - 1];
        auto pre_entry = preimages[0];
        foreach (ref entry; preimages[1 .. $])
        {
            entry = hashFull(pre_entry);
            pre_entry = entry;
        }
        writefln("%s: %s", name, preimages[$ - 1]);

        // Generate signature noise
        auto random_seed = preimages[$ - 1];
        Enrollment result = {
            utxo_key: utxos[name],
            cycle_length: 20,
            random_seed: random_seed,
        };
        ulong offset = 0;
        const Pair noise = Pair.fromScalar(
            Scalar(hashMulti(key_pair.v, "consensus.signature.noise", offset)));

        // We're done, sign & return
        result.enroll_sig = sign(key_pair, noise, result);
        writefln("%s Sig: %s", name, result.enroll_sig);
    }

    writeln("=============================================================");
    foreach (name, secret; secrets)
    {
        uint seek_nonce = 0;
        auto key_pair = Pair.fromScalar(secretKeyToCurveScalar(secret));
        key_pairs[name] = key_pair;
        const cycle_seed = hashMulti(
                    key_pair.v, "consensus.preimages", seek_nonce);
        auto count = 5040000/20;
        auto data = new Hash[](count);
        data[0] = cycle_seed;
        Hash seed = cycle_seed;
        Hash last_entry;
        foreach (ref entry; data[1 .. $])
        {
            foreach (idx; 0 .. 20)
                seed = hashFull(seed);
            entry = seed;
            last_entry = entry;
        }

        auto preimages = new Hash[](20);
        preimages[0] = data[$ - 1];
        auto pre_entry = preimages[0];
        foreach (ref entry; preimages[1 .. $])
        {
            entry = hashFull(pre_entry);
            pre_entry = entry;
        }
        writefln("%s: %s", name, preimages[$ - 1]);

        // Generate signature noise
        auto random_seed = preimages[$ - 1];
        Enrollment result = {
            utxo_key: utxos[name],
            cycle_length: 20,
            random_seed: random_seed,
        };
        ulong offset = 0;
        const Pair noise = Pair.fromScalar(
            Scalar(hashMulti(key_pair.v, "consensus.signature.noise", offset)));

        // We're done, sign & return
        result.enroll_sig = sign(key_pair, noise, result);
        writefln("%s Sig: %s", name, result.enroll_sig);
    }

    writeln("=============================================================");


    foreach (name, secret; secrets)
    {
        uint seek_nonce = 0;
        auto key_pair = Pair.fromScalar(secretKeyToCurveScalar(secret));
        key_pairs[name] = key_pair;
        const cycle_seed = hashMulti(
                    key_pair.v, "consensus.preimages", seek_nonce);
        auto count = 5000;
        auto data = new Hash[](count);
        data[0] = cycle_seed;
        Hash seed = cycle_seed;
        Hash last_entry;

        MonoTime before = MonoTime.currTime;
        writeln("start");
        foreach (ref entry; data[1 .. $])
        {
            foreach (idx; 0 .. 1008)
                seed = hashFull(seed);
            entry = seed;
            last_entry = entry;
        }

        MonoTime after = MonoTime.currTime;
        Duration timeElapsed = after - before;
        writeln("end: ", timeElapsed);

        auto preimages = new Hash[](1008);
        preimages[0] = data[$ - 1];
        auto pre_entry = preimages[0];
        foreach (ref entry; preimages[1 .. $])
        {
            entry = hashFull(pre_entry);
            pre_entry = entry;
        }
        writefln("%s: %s", name, preimages[$ - 1]);

        // Generate signature noise
        auto random_seed = preimages[$ - 1];
        Enrollment result = {
            utxo_key: utxos[name],
            cycle_length: 1008,
            random_seed: random_seed,
        };
        ulong offset = 0;
        const Pair noise = Pair.fromScalar(
            Scalar(hashMulti(key_pair.v, "consensus.signature.noise", offset)));

        // We're done, sign & return
        result.enroll_sig = sign(key_pair, noise, result);
        writefln("%s Sig: %s", name, result.enroll_sig);
    }


}
