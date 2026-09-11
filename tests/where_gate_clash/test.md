# where_gate_clash (negative)

**Validates (README §4, §9):** two gated methods on the same rung, in one
module, matching the same argument, with NO order declared between their
predicates = comptime error at the call.

`Integer` and `Signed` overlap — every signed integer answers both — so
`g(1)` matches `g(x::T) where T <: Integer` and `g(x::T) where T <:
Signed` alike. Both sit at rank 2, because a gate lifts a binder to the
predicate rung. Nothing breaks the tie: no `<:` edge relates the two
predicate words, and jpp builds no prover, so a missing edge is simply
false. Neither dominates, both are maximal, same module — the promise is
the ambiguity error, naming the cure.

`where_gate_pass` is this exact folder plus one line, `<:(Signed,
Integer) = true`, which cures it. Diff the two to see the whole promise:
overlap without a declared order is an error, and declaring the order is
what makes it a choice.

`expect.err` greps `call of 'g' is AMBIGUOUS`; compile SUCCESS fails the
case.
