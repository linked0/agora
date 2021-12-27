/*******************************************************************************

    Just testing

    Copyright:
        Copyright (c) 2019-2021 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.test.DebugTest;

version (unittest):

import agora.consensus.data.UTXO;
import agora.consensus.protocol.Nominator;
import agora.crypto.Hash;
import agora.utils.PrettyPrinter;
import agora.test.Base;

import scpd.types.Stellar_types : NodeID;

import core.thread;
import std.typecons: tuple;

// From agora.test.Fee
// Normal operation, every `payout_period`th block should
// include coinbase outputs to validators
// version (none)
unittest
{
    TestConf conf;
    conf.consensus.quorum_threshold = 100;
    conf.consensus.payout_period = 5;
    auto network = makeTestNetwork!TestAPIManager(conf);
    network.start();
    scope(exit) network.shutdown();
    scope(failure) network.printLogs();
    network.waitForDiscovery();

    auto nodes = network.clients;
    auto node_1 = nodes[0];

    // Get the genesis block, make sure it's the only block externalized
    auto blocks = node_1.getBlocksFrom(0, 2);
    assert(blocks.length == 1);
    writeln(blocks[0].prettify);

    void createAndExpectNewBlock (Height new_height)
    {
        writeln("===========================\n", new_height);

        // create tx for a single block
        auto utxo_pairs = node_1.getSpendables(100.coins, OutputType.Payment);

        // create and send tx to all nodes
        network.postAndEnsureTxInPool(
            TxBuilder(WK.Keys.AAA.address)
            .attach(utxo_pairs.map!(p => tuple(p.utxo.output, p.hash)))
            .deduct(1.coins).sign());
        
        network.expectHeightAndPreImg(new_height, blocks[0].header);

        // add next block
        blocks ~= node_1.getBlocksFrom(new_height, 1);

        auto cb_txs = blocks[$-1].txs.filter!(tx => tx.isCoinbase).array;
        // Regular block
        if (blocks[$-1].header.height < 2 * conf.consensus.payout_period
            || blocks[$-1].header.height % conf.consensus.payout_period)
            assert(cb_txs.length == 0);
        else // Payout block
        {
            writeln("cb_txs.length: ", cb_txs.length);
            assert(cb_txs.length == 1);
            auto cb_outs = cb_txs[0].outputs;
            assert(cb_outs.length == 1 + blocks[0].header.enrollments.length);
        }
        writeln(blocks[$-1].prettify);
    }

    // create GenesisValidatorCycle - 1 blocks
    foreach (block_idx; 1 .. GenesisValidatorCycle)
    {
        createAndExpectNewBlock(Height(block_idx));
    }

    auto amt = Amount(1.coins);
    auto amt2 = Amount(10000);
    auto amt3 = Amount(100000);
    auto amt4 = Amount(1000000);
    writeln("amt: ",amt.prettify);
    writeln("amt2: ", amt2.prettify);
    writeln("amt3: ", amt3.prettify);
    writeln("amt4: ", amt4.prettify);
}

unittest
{
    TestConf conf;
    conf.consensus.quorum_threshold = 100;
    conf.consensus.payout_period = 5;
    auto network = makeTestNetwork!TestAPIManager(conf);
    network.start();
    scope(exit) network.shutdown();
    scope(failure) network.printLogs();
    network.waitForDiscovery();

    auto nodes = network.clients;
    auto node_1 = nodes[0];

    // Get the genesis block, make sure it's the only block externalized
    auto blocks = node_1.getBlocksFrom(0, 2);
    assert(blocks.length == 1);
    writeln(blocks[0].prettify);
    auto hash = UTXO.getHash(blocks[0].txs[0].hashFull(), 0);
    writeln("UTXO hash: ", hash);
    hash = UTXO.getHash(blocks[0].txs[0].hashFull(), 1);
    writeln("UTXO hash: ", hash);
    hash = UTXO.getHash(blocks[0].txs[0].hashFull(), 2);
    writeln("UTXO hash: ", hash);
}

unittest
{
    Hash b = Hash("0x09dc319d8c52f4527c10170b28c148d8406763a19df3e7ece18d4f454b9cb68e3dd6954da28b5e75a46d8daf1ad7c8fef25a344616a295f59772e9e2f812577c");
    auto hash = UTXO.getHash(b, 0);
    writeln("0: ", hash);
    hash = UTXO.getHash(b, 1);
    writeln("1: ", hash);
}