/*******************************************************************************

    Check that the node does not break in the situation where a nomination
    and regenerating quorums are interleaved, especially when a block is
    externalized from periodic catchup.

    Copyright:
        Copyright (c) 2019-2021 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.test.NominatingCatchup;

version (unittest):

import agora.consensus.protocol.Nominator;
import agora.test.Base;

import scpd.types.Stellar_types : NodeID;

import core.thread;

private class CustomNominator : Nominator
{
extern (D):
    /// Ctor
    mixin ForwardCtor!();

    ///
    public override void setQuorumConfig (ref const(NodeID) node_id,
        const(QuorumConfig)[NodeID] quorums) nothrow @safe
    {
        scope(failure) assert (0);
        this.checkNominate();
        super.setQuorumConfig(node_id, quorums);
    }
}

private class CustomValidator : TestValidatorNode
{
    mixin ForwardCtor!();

    ///
    protected override CustomNominator makeNominator (
        Parameters!(TestValidatorNode.makeNominator) args)
    {
        return new CustomNominator(
            this.params, this.config.validator.key_pair, args,
            this.cacheDB, this.config.validator.nomination_interval,
            &this.acceptBlock);
    }
}

private class CustomAPIManager : TestAPIManager
{
    mixin ForwardCtor!();

    ///
    public override void createNewNode (Config conf, string file, int line)
    {
        if (this.nodes.length == 0)
            this.addNewNode!CustomValidator(conf, file, line);
        else
            super.createNewNode(conf, file, line);
    }
}

/// On a block being externalized, the timer for a nomination process
/// stops and the newly constructed quorums is set. But there is a
/// situation where the previously called nomination process is running
/// while setting new quorums, which is a probable situation but we did
/// not account for in our code. Setting new quorums should be completed
/// at the situation without a crach.
unittest
{
    TestConf conf = {
        outsider_validators : 1,
    };
    auto network = makeTestNetwork!CustomAPIManager(conf);
    network.start();
    scope(exit) network.shutdown();
    scope(failure) network.printLogs();
    network.waitForDiscovery();
    auto nodes = network.clients;
    auto catchup_node = 0;

    network.generateBlocks(Height(GenesisValidatorCycle - 2));
    auto b18 = nodes[catchup_node].getBlocksFrom(GenesisValidatorCycle - 2, 2)[0];
    assert(b18 != Block.init);

    // make sure outsiders are up to date
    network.expectHeight(iota(GenesisValidators + 1), Height(GenesisValidatorCycle - 2));

    // prepare frozen outputs for the outsider validator to enroll
    network.postAndEnsureTxInPool(network.freezeUTXO(only(GenesisValidators)));

    // Block 19
    network.generateBlocks(Height(GenesisValidatorCycle - 1));
    network.expectHeight(iota(GenesisValidators + 1), Height(GenesisValidatorCycle - 1));

    // enroll the outsider
    auto enroll = nodes[GenesisValidators].setRecurringEnrollment(true);
    assert(enroll != Enrollment.init);

    // Block 20 and check the all the enrollements to be validators
    network.generateBlocks(iota(GenesisValidators), Height(GenesisValidatorCycle));
    network.expectHeight(Height(GenesisValidatorCycle));
    auto b20 = nodes[catchup_node].getBlocksFrom(GenesisValidatorCycle, 2)[0];
    assert(b20.header.enrollments.length == 7);

    network.restart(nodes[catchup_node]);
    network.expectHeight([catchup_node], Height(GenesisValidatorCycle));
}
