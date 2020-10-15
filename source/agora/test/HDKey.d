/*******************************************************************************

    Contains tests for generating and verifying HD Keys

    Copyright:
        Copyright (c) 2020 BOS Platform Foundation Korea
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.test.HDKey;

version (unittest):

import agora.common.crypto.Key;
import agora.test.Base;

unittest
{
    immutable seedStr = `SBBUWIMSX5VL4KVFKY44GF6Q6R5LS2Z5B7CTAZBNCNPLS4UKFVDXC7TQ`;
    KeyPair kp = KeyPair.fromSeed(Seed.fromString(seedStr));

    writeln("HDKey secret:", kp.secret[]);
    writeln("HDKey secret2:", kp.secret2[]);

    writeln("HDKey address:", kp.address[]);
    writeln("HDKey address2:", kp.address2[]);
}
