# lattice_gap

**Validates (negative):** the order is consulted PAIRWISE BETWEEN
CANDIDATES, so a declared chain conducts only through classes that
themselves carry a method at the call.

`order.jpp` authors the full chain `Tiny <: Small <: Numeric`. An
`int8` answers `Tiny` and `Numeric`. But `rules.jpp` gates methods only
on the two ENDS — nothing is gated on `Small` — so the candidate set is
`{Tiny, Numeric, bare}`. Resolution asks `wordLeq(Tiny, Numeric)`,
finds no edge with that exact pair, and gets `false` in both
directions. `Tiny` and `Numeric` are incomparable, both survive as
maxima, and the call is an ambiguity error.

**Why `tests/lattice` passes without its transitive edge.** There, the
middle classes `Small` and `Signed` each carry a method. `Numeric` is
knocked out of the maxima by `Small` and by `Signed`, and those are
knocked out by `SmallSigned`. Transitivity is never needed because the
intermediate nodes are present to do the eliminating. Remove the
middle method and the same tree stops resolving.

**Whose problem this is.** Both maxima live in `rules.jpp`, so this is
the SAME-MODULE clash: the definer wrote two methods that overlap and
did not say which is narrower. The error fires there because position —
the caller's only tie-breaker — cannot separate two methods in one
file. That is the whole rule at `resolve`: maxima from different
modules are settled silently by context order; maxima from one module
are refused.

**The caller is not stuck.** `tests/lattice_bridge` is this same
library, unedited, plus one `<:` fact in the CALLER's module. It
compiles and answers 10. The order word is ordinary and resolves in the
caller's context, so a missing link is always fixable downstream by
whoever assembled the world — no fork of the library required.

**The sharp edge is the OTHER case.** Split the two `gap` methods
across two modules and the same missing link stops being an error:
different homes, so context order silently picks one. A question about
which class is narrower then gets answered by `using` order — which is
exactly what authoring `<:` exists to prevent. The loud failure here is
the friendly case.

**This is not an open question.** README §9 already ratifies it: NO
transitive closure, chains are authored or absent, and implication
between predicates is AUTHORED, never proven — jpp builds no prover.
The cure is one line, `<:(Tiny, Numeric) = true`, written by whoever
knows it is true. What this case adds is only the DEMONSTRATION that a
chain which appears to conduct in `tests/lattice` was never conducting
at all; it was the middle class's own method doing the eliminating.

**What remains actionable is the diagnostic.** The error lists two
maximal candidates, which is accurate but unhelpful — the author has to
work out that the classes are incomparable and which edge would fix it.
Naming the missing link would say what the two-candidate list cannot.
