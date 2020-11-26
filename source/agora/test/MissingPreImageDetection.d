/*******************************************************************************

    Contains tests for the validators not revealing their pre-images. There
    are four cases that the validators do not reveal as follows.

    HHHHHH

    Copyright:
        Copyright (c) 2020 BOS Platform Foundation Korea
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.test.MissingPreImageDetection;

import agora.common.crypto.Key;
import agora.common.Config;
import agora.common.Hash;
import agora.common.Serializer;
import agora.common.Task;
import agora.consensus.data.Block;
import agora.consensus.data.Params;
import agora.consensus.data.Enrollment;
import agora.consensus.data.PreImageInfo;
import agora.consensus.data.Transaction;
import agora.consensus.EnrollmentManager;
import agora.consensus.protocol.Data;
import agora.network.Clock;
import agora.network.NetworkManager;
import agora.node.Ledger;
import agora.utils.Test;
import agora.test.Base;

import scpd.types.Utils;
import scpd.types.Stellar_SCP;

import core.stdc.stdint;
import core.stdc.time;
import core.thread;

import geod24.Registry;

version (unittest):

/*******************************************************************************

    HHHHHH Check a pre-image of the specified distance is revealed

    Params:
        HHHHHH

*******************************************************************************/

private void unexpectBlock (Clients)(Clients clients, Height height)
{
    foreach (_; 0 .. 10)
    {
        clients.each!(node => retryFor(
            node.getBlockHeight() < height, 1.seconds));
    }
}


private class MissingPreImageEM : EnrollmentManager
{
    ///
    public this (string db_path, KeyPair key_pair,
        immutable(ConsensusParams) params)
    {
        super(db_path, key_pair, params);
    }

    /// This does not reveal pre-images intentionally
    public override bool getNextPreimage (out PreImageInfo preimage,
        Height height) @safe
    {
        // return super.getNextPreimage(preimage, height);
        return false;
    }
}

private class NoPreImageVN : TestValidatorNode
{
    ///
    public this (Config config, Registry* reg, immutable(Block)[] blocks,
                    ulong txs_to_nominate, shared(time_t)* cur_time)
    {
        super(config, reg, blocks, txs_to_nominate, cur_time);
    }

    protected override EnrollmentManager getEnrollmentManager (
        string data_dir, in ValidatorConfig validator_config,
        immutable(ConsensusParams) params)
    {
        return new MissingPreImageEM(":memory:", validator_config.key_pair,
            params);
    }
}

/// This test is for the case A.
/// Test for detecting the validator never sending any pre-image after
/// its initial enrollment.
unittest
{
    static class BadAPIManager : TestAPIManager
    {
        ///
        public this (immutable(Block)[] blocks, TestConf test_conf,
            time_t initial_time)
        {
            super(blocks, test_conf, initial_time);
        }

        ///
        public override void createNewNode (Config conf, string file, int line)
        {
            if (this.nodes.length == 5)
            {
                auto time = new shared(time_t)(this.initial_time);
                auto api = RemoteAPI!TestAPI.spawn!NoPreImageVN(
                    conf, &this.reg, this.blocks, this.test_conf.txs_to_nominate,
                    time, conf.node.timeout);
                this.reg.register(conf.node.address, api.tid());
                this.nodes ~= NodePair(conf.node.address, api, time);
            }
            else
                super.createNewNode(conf, file, line);
        }
    }

    import std.stdio; // HHHHHH
    import core.thread;

    TestConf conf = {
        recurring_enrollment : false,
    };
    auto network = makeTestNetwork!BadAPIManager(conf);
    network.start();
    scope(exit) network.shutdown();
    scope(failure) network.printLogs();
    network.waitForDiscovery();

    auto nodes = network.clients;
    auto bad_validator = nodes[$ - 1];
    Enrollment bad_enroll;
    auto genesis_header = network.blocks[0].header;
    auto spendable = network.blocks[$ - 1].spendable().array;

    // discarded UTXOs (just to trigger block creation)
    auto txs = spendable[0 .. 8].map!(txb => txb.sign()).array;

    Thread.sleep(5.seconds);

    // block 1
    txs.each!(tx => nodes[0].putTransaction(tx));
    network.expectBlock(Height(1));
}

/// This test is for the case A.
/// Test for detecting the validator never sending any pre-image after
/// its initial enrollment.
unittest
{
    static class BadNominator : TestNominator
    {
        /// Ctor
        public this (immutable(ConsensusParams) params, Clock clock,
            NetworkManager network, KeyPair key_pair, Ledger ledger,
            TaskManager taskman, string data_dir, ulong txs_to_nominate,
            shared(time_t)* curr_time)
        {
            super(params, clock, network, key_pair, ledger, taskman,
                data_dir, txs_to_nominate);
        }

    extern (C++):

        public override ValidationLevel validateValue (uint64_t slot_idx,
            ref const(Value) value, bool nomination) nothrow
        {
            scope(failure) assert(0);

            ValidationLevel ret;
            () @trusted {
                auto data = deserializeFull!ConsensusData(value[]);
                import std.stdio;
                writeln("preimage root: ", data.preimage_root);
                writeln("missing_validator: ", data.missing_validators);
                data.missing_validators ~= 2;
                auto next_value = data.serializeFull().toVec();
                ret = super.validateValue(slot_idx, next_value, nomination);
            }();

            return ret;
        }
    }

    static class BadNominatingVN : TestValidatorNode
    {
        ///
        public this (Config config, Registry* reg, immutable(Block)[] blocks,
                        ulong txs_to_nominate, shared(time_t)* cur_time)
        {
            super(config, reg, blocks, txs_to_nominate, cur_time);
        }

        ///
        protected override TestNominator getNominator (
            immutable(ConsensusParams) params, Clock clock,
            NetworkManager network, KeyPair key_pair, Ledger ledger,
            TaskManager taskman, string data_dir)
        {
            return new BadNominator(
                params, clock, network, key_pair, ledger, taskman,
                data_dir, this.txs_to_nominate, this.cur_time);
        }
    }

    static class BadAPIManager : TestAPIManager
    {
        ///
        public this (immutable(Block)[] blocks, TestConf test_conf,
            time_t initial_time)
        {
            super(blocks, test_conf, initial_time);
        }

        ///
        public override void createNewNode (Config conf, string file, int line)
        {
            if (this.nodes.length == 0)
            {
                auto time = new shared(time_t)(this.initial_time);
                auto api = RemoteAPI!TestAPI.spawn!NoPreImageVN(
                    conf, &this.reg, this.blocks, this.test_conf.txs_to_nominate,
                    time, conf.node.timeout);
                this.reg.register(conf.node.address, api.tid());
                this.nodes ~= NodePair(conf.node.address, api, time);
            }
            else if (this.nodes.length >= 4)
            {
                auto time = new shared(time_t)(this.initial_time);
                auto api = RemoteAPI!TestAPI.spawn!BadNominatingVN(
                    conf, &this.reg, this.blocks, this.test_conf.txs_to_nominate,
                    time, conf.node.timeout);
                this.reg.register(conf.node.address, api.tid());
                this.nodes ~= NodePair(conf.node.address, api, time);
            }
            else
                super.createNewNode(conf, file, line);
        }
    }

    import std.stdio; // HHHHHH
    import core.thread;

    writeln("Hi NoPreImageBadNominatingVN~");

    TestConf conf = {
        recurring_enrollment : false,
    };
    auto network = makeTestNetwork!BadAPIManager(conf);
    network.start();
    scope(exit) network.shutdown();
    scope(failure) network.printLogs();
    network.waitForDiscovery();

    auto nodes = network.clients;
    auto genesis_header = network.blocks[0].header;
    auto spendable = network.blocks[$ - 1].spendable().array;

    // discarded UTXOs (just to trigger block creation)
    auto txs = spendable[0 .. 8].map!(txb => txb.sign()).array;

    Thread.sleep(5.seconds);

    // try to make block 1
    txs.each!(tx => nodes[0].putTransaction(tx));
    unexpectBlock(nodes, Height(1));
}
