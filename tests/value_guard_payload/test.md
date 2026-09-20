# A text packet's tag does not reveal its length

A packet encoder wants to compress messages longer than 80 bytes:

```jpp
encoding(packet<:TextPacket) where shouldCompress(packet.payload) = "compressed"
encoding(<:Any) = "plain"
```

The packet comes from a runtime receiver. Dispatch knows that its selected tag
is `text`, but it does not know the incoming string's length. The native
`shouldCompress` predicate would have to read that runtime payload.

**Expected:** compilation rejects the qualifier with
`value qualifier cannot pass runtime data to ground`. It must never substitute
an undefined string and accidentally select `"plain"`.

This is an intentional boundary of the current implementation. A tag/type-only
predicate works in [the packet-routing case](../value_guard_variant/test.md).
Length-based runtime branching needs a later extension; this test prevents us
from claiming that extension already works.
