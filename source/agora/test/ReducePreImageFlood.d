/*******************************************************************************

    Check that a validator sends a pre-image only to peers that do not
    have a proper height of pre-image.

    Copyright:
        Copyright (c) 2019-2022 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.test.ReducePreImageFlood;

version (unittest):

import agora.common.Set;
import agora.consensus.data.PreImageInfo;
import agora.test.Base;

import core.atomic;
import core.thread.osthread : Thread;

package immutable Green = "\u001b[32m";

/// Situation:
/// Expectation:
unittest
{
    static class CustomValidator : TestValidatorNode
    {
        mixin ForwardCtor!();

        private shared int* same_preimage_count;

        ///
        public this (Parameters!(TestValidatorNode.__ctor) args,
            shared(int)* same_preimage_count)
        {
            this.same_preimage_count = same_preimage_count;
            super(args);
        }

        ///
        public override bool postPreimage (in PreImageInfo preimage) @safe
        {
            import agora.utils.PrettyPrinter;
            writeln("utxo of preimage: ", preimage.prettify);
            auto infos = this.getPreimages(Set!Hash.from(preimage.utxo.only));
            if (infos[0].height == preimage.height)
                atomicOp!"+="(*this.same_preimage_count, 1); 
            return super.postPreimage(preimage);
        }
    }

    static class CustomAPIManager : TestAPIManager
    {
        mixin ForwardCtor!();

        public static shared int same_preimage_count = 0;

        /// set base class
        public override void createNewNode (Config conf, string file, int line)
        {
            if (this.nodes.length == 5)
                this.addNewNode!CustomValidator(conf, &this.same_preimage_count,
                    file, line);
            else
                super.createNewNode(conf, file, line);
        }
    }

    TestConf config;
    auto network = makeTestNetwork!CustomAPIManager(config);
    network.start();
    scope(exit) network.shutdown();
    scope(failure) network.printLogs();
    network.waitForDiscovery();
    network.generateBlocks(Height(1));
    Thread.sleep(config.preimage_reveal_interval * 2);
    auto old_same_preimage_count = CustomAPIManager.same_preimage_count;
    Thread.sleep(config.preimage_reveal_interval * 2);
    assert(CustomAPIManager.same_preimage_count == old_same_preimage_count);
}
