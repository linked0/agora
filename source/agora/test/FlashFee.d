/*******************************************************************************

    Contains tests for the fee distribution

    Copyright:
        Copyright (c) 2019-2021 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.test.FlashFee;

import agora.test.Base;

// Normal operation, every `payout_period`th block should
// include coinbase outputs to validators
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

    Transaction[] txs;

    void createAndExpectNewBlock (Height new_height)
    {
        // create enough tx's for a single block
        txs = blocks[new_height - 1].spendable().map!(txb => txb
            .deduct(Amount.UnitPerCoin).sign()).array();

        // send them to all nodes
        txs.each!(tx => nodes.each!(node => node.postTransaction(tx)));

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
            assert(cb_txs.length == 1);
            auto cb_outs = cb_txs[0].outputs;
            assert(cb_outs.length == 1 + blocks[0].header.enrollments.length);
        }
    }

    // create GenesisValidatorCycle - 1 blocks
    foreach (block_idx; 1 .. GenesisValidatorCycle)
    {
        createAndExpectNewBlock(Height(block_idx));
    }
}