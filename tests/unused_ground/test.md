# unused_ground

An annotated input has a role in the signature even when the body ignores
its value. This is valid for both grounds and ordinary bodies: constant
methods still select by input type, predicate gates, or repeated type
constraints. An anonymous spelling is optional.

The original ground now runs: `x::int64` is unused, while `xx` is returned.
The string `"x"` and the longer name `xx` must not cause an unused Zig local
to be emitted for `x`. `unused_untyped_ground` separately rejects the same
ground with a fresh, unannotated `x`.
