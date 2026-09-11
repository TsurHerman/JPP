# lattice_bridge

**Validates (README §9):** a gap in the order is the CALLER's to close.
`<:` is an ordinary word resolving in the caller's context, so a fact
the library never stated can be supplied downstream, about two classes
the caller does not own.

This tree is `tests/lattice_gap` — which does not compile — with
`preds.jpp`, `order.jpp` and `rules.jpp` unchanged. The only additions
are `bridge.jpp`, holding the single fact `<:(Tiny, Numeric) = true`,
and the `using bridge` line in `main.jpp`.

**Why the library could not have fixed it for everyone.** The author of
`rules.jpp` gated on `Tiny` and on `Numeric` and genuinely may not know
which should win — that is a claim about the class order, not about the
methods. Shipping the clash and letting each caller state the edge is
the honest factoring, and it is the same move as
`tests/order_injection` applied to a missing transitive link rather
than to two unrelated classes.

**Contrast with `tests/order_refines`.** There the edge decides BETWEEN
two comparable answers and reversing it flips the winner. Here the edge
does not choose a winner so much as connect a chain that was already
authored end to end; without it the two ends are simply incomparable.
