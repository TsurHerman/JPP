# Static binding cycles are invalid

Module imports may be cyclic, but two constants cannot require each other's value.
Zig's declaration dependency check rejects the cycle during static evaluation.
