# where_gate

**Two spellings, one meaning.** `terse` repeats `describe`'s ladder in
the short slot form — `terse(x<:Integer)` where `describe` wrote
`describe(x::T) where T <: Integer` — and answers the same rung for
every argument. README §4: `x<:Integer` ≡ `x::T where Integer(T)` with
T fresh, so jppc lowers it to a binder plus a gate and the machinery
never learns there were two spellings. `::` takes a TYPE and `<:` takes
a PREDICATE; the rank is read off the symbol, which is why `x::Integer`
is ill-formed rather than a third way to write this.

**Validates (README §4, §8):** `where` carries a PREDICATE GATE on
qualification, and `where T <: Integer` is sugar for the gate
`Integer(T)`.

Three promises, one case:

**Predicates are ordinary words, not a type tree.** `preds.jpp` defines
`Integer(T::type)::bool` — a normal method whose slot is qualed on
`type`, so the argument IS a type travelling as a value and the body
reads its structure at comptime. There is no `Integer <: Real <: Number`
hierarchy anywhere; the predicate is the whole of it.

**A gate is METHOD data, not a slot qualifier.** That is what lets it
compose with repeated-binder identity: in `pairup(a::T, b::T) where T <:
Integer`, the repeated `T` still demands one type and the gate then
demands that type be an integer. Both constraints survive because they
live in different places. `pairup(1, 1.5)` fails identity;
`pairup(1.5, 2.5)` passes identity and fails the gate; only
`pairup(1, 2)` gets through.

**A gated binder sits on the PREDICATE rung.** The ledger's ladder is
`::` exact 3 > `<:` predicate 2 > bare 1, and `x<:Integer` is the same
statement as `x::T where T <: Integer`, so the two must rank alike.
`describe(1)` answers 3 because the exact input type outranks a gate.
Its fallback is now the ordinary Any predicate, also on rank 2.
`describe(1.5)` answers 2 because Base explicitly authors other classes
below Any; `describe("hi")` answers 0 because only Any accepts strings.
Both spellings use that same authored order. The `any` case separately
checks that a predicate beats an unconstrained binder at rank 1.

`kindof` exists because `describe`'s exact rung hides the Integer gate
ever winning — with the exact method gone, the gate is what answers.

**Gates do not leak onto callers.** `main.jpp` never imports `preds`. A
gate resolves caller-first with the defining module's static context as
fallback — the same reach a body gets — so applicability stays
caller-derived (a caller that extends `Integer` leads by position)
without every caller having to import the predicate module.
The caller imports Any here for its order rule when comparing gates;
predicate applicability and the context used for order comparisons are
distinct. `any_override` tests membership with Any imported only by the library.
