module agora.test.JayTest;

version (unittest):

import agora.api.FullNode;
import agora.crypto.Key;
import agora.test.Base;
import agora.consensus.state.UTXOSet;

import core.thread : Thread;

unittest
{
    Hash b = Hash("0xe8ead5820f3252a334cd798775435b7ae035879254d5744c6b33fd7bb60da9fffbcb90ab886d808fd16f03ba6602ce850e7d01c0a389f86bf9bb9fa991b14682");
    auto hash = UTXO.getHash(b, 0);
    writeln("0: ", hash);
    hash = UTXO.getHash(b, 1);
    writeln("1: ", hash);
}
