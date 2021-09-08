/*******************************************************************************

    Contains tests for getting missing enrollments from the network

    Copyright:
        Copyright (c) 2019-2021 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.test.GetEnrollments;

version (unittest):

import agora.api.FullNode;
import agora.common.Amount;
import agora.common.Config;
import agora.consensus.data.Block;
import agora.consensus.data.Enrollment;
import agora.consensus.data.Transaction;
import agora.crypto.Key;
import agora.test.Base;

import core.atomic : atomicLoad;
import core.thread;

/// Situation: There are six validators enrolled in Genesis block.
///     But a validator can not receive any enrollments in the case
///     of an abnormal situation. The validator tries to get missing
///     enrollments periodically
/// Expectation: The validator ends up restoring misssing enrollments
///     from other nodes.
unittest
{
    static class CustomValidator : TestValidatorNode
    {
        mixin ForwardCtor!();

        private shared bool* enable_catchup;

        ///
        public this (Parameters!(TestValidatorNode.__ctor) args,
            shared(bool)* enable_catchup)
        {
            this.enable_catchup = enable_catchup;
            super(args);
        }

        ///
        protected override void catchupTask () nothrow
        {
            if (atomicLoad(*this.enable_catchup))
                super.catchupTask();
        }
    }

    static class CustomAPIManager : TestAPIManager
    {
        mixin ForwardCtor!();

        public static shared bool enable_catchup = false;

        /// set base class
        public override void createNewNode (Config conf, string file, int line)
        {
            if (this.nodes.length == GenesisValidators - 1)
                this.addNewNode!CustomValidator(conf, &this.enable_catchup,
                    file, line);
            else
                super.createNewNode(conf, file, line);
        }
    }

    TestConf conf = {
        outsider_validators : 1,
        recurring_enrollment : false
    };
    auto all_validators = GenesisValidators + conf.outsider_validators;
    auto network = makeTestNetwork!CustomAPIManager(conf);
    network.start();
    scope(exit) network.shutdown();
    scope(failure) network.printLogs();
    network.waitForDiscovery();

    auto bad_node = network.clients[GenesisValidators - 1];
    auto outsider = network.nodes[GenesisValidators];

    network.generateBlocks(Height(GenesisValidatorCycle - 2));

    // make sure outsiders are up to date
    network.expectHeight(iota(GenesisValidators, all_validators),
        Height(GenesisValidatorCycle - 2));

    // the bad validator becomes unresponsive
    bad_node.filter!(API.postTransaction);

    // prepare frozen outputs for the outsider validator to enroll
    const key = outsider.getPublicKey().key;
    network.blocks[0].spendable().drop(1).takeExactly(1)
        .map!(txb => txb
            .split([key]).sign(OutputType.Freeze))
            .each!(tx => network.nodes[0].postTransaction(tx));

    // Block 19 we add the frozen utxo for the outsider validator
    // The bad validator don't receive this `postTransaction` request
    auto target_nodes = iota(GenesisValidators - 1).array;
    target_nodes ~= GenesisValidators;
    network.generateBlocks(target_nodes, Height(GenesisValidatorCycle - 1));
 
    // enroll the outsider
    auto enroll = network.clients[GenesisValidators].setRecurringEnrollment(true);

    // re-enroll all the validators
    iota(GenesisValidators).each!(i => network.enroll(iota(GenesisValidators), i));

    // enable `catchupTask` for the bad validator and clear filter
    CustomAPIManager.enable_catchup = true;
    bad_node.clearFilter();

    auto gotten_enroll = bad_node.getEnrollment(enroll.utxo_key);
    assert(gotten_enroll == Enrollment.init);

    // make sure the bad validator is up to date    
    network.expectHeight([GenesisValidators - 1], Height(GenesisValidatorCycle - 1));

    // check the missing enrollment to be restored
    retryFor(bad_node.getEnrollment(enroll.utxo_key) == enroll,
        2 * conf.node.enrollment_catchup_interval,
        format!"The enrollment (%s) not in pool of the bad validator"(enroll.utxo_key));

    network.generateBlocks(iota(all_validators), Height(GenesisValidatorCycle));
    auto b20 = network.nodes[0].getBlocksFrom(GenesisValidatorCycle, 1)[0];
    assert(b20.header.enrollments.length == 7);

    import std.datetime : Clock, dur;
    import std.file : tempDir, exists, isFile, read, write;
    import std.path : buildPath;
    import std.socket : Socket, SocketException, TcpSocket, Address, InternetAddress, Internet6Address, AddressFamily, SocketOption, SocketOptionLevel;
    import std.stdio;
    import std.string : indexOf, strip;
    string cache;
    cache = buildPath(tempDir(), ".dub.my-ip");
	void[] data = read(cache);
    writeln("static publicAddress: ", cast(string)data[4..$]);
}
