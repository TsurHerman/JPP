# order_refines

**Validates (README §4):** `<:` is an ORDINARY WORD, and within the
predicate rung a declared edge refines dispatch.

Two programs, identical predicates and identical gated methods, opposite
authored edges, opposite winners. `g(x::T) where T <: Wide` and
`g(x::T) where T <: Signed` both match `g(1)` and both sit at rank 2, so
nothing separates them except the order. Declare `Wide <: Signed` and
the lower gate answers 1; declare `Signed <: Wide` and it answers 2.
Remove the edge entirely and the two collide — that is the
`where_gate_clash` case.

**Both directions are honest here, which is the whole reason these two
classes were chosen.** `Wide` and `Signed` overlap without either
containing the other: `uint32` is Wide and not Signed, `int8` is Signed
and not Wide, `int64` is both. So no containment fixes their order and
nothing could derive one. Whichever edge a program declares is a
priority it wanted, not a false statement about the classes.

This case deliberately does NOT use a pair like `Signed` and `Integer`.
There the containment is real and only `Signed <: Integer` is true;
declaring the reverse to show off the mechanism would teach a falsehood
about classes that mean something. Order the incomparable pairs; leave
the true containments pointing the way they point.

**Defined names are required.** Each order module imports `preds`, which
actually defines and exports `Signed` and `Wide`. Their names therefore
refer to existing class values. Without that import they introduce fresh
variables; a constant body would leave them unused and fail compilation.
`undeclared_order` pins that error, including when the caller has imported
the missing definitions. The same rule applies to ordinary signatures
(`declaration_names`), with no special name-literal shortcut for `<:`.

**Stratification is what makes this terminate.** Refinement asks the
order a question while resolution is still running, so `<:` resolves at
STRATUM 0 — the bare rank ladder, no edge refinement, no policy word.
Ranking the order methods therefore does not consult the order itself.
Arbitrary recursion through user bodies is a separate, unfinished mechanism.
