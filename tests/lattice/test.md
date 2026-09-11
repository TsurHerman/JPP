# lattice

**Validates (README §4):** predicates plus authored `<:` edges express
a LATTICE, not a tree. A class may sit below two incomparable classes
at once.

```
        Numeric
        /     \
     Small   Signed
        \     /
      SmallSigned
```

Every `int16` answers all four predicates, so all four gated methods
are candidates on every such call. Nothing about the types decides;
the authored order does.

**Why this is not expressible as a tree.** Single inheritance forces
`SmallSigned` to pick one parent. Julia's abstract hierarchy has this
exact limitation — it is why `LinearAlgebra` cannot make `Diagonal` a
subtype of both `UpperTriangular` and `LowerTriangular` and reaches for
traits instead. Here the diamond is four lines of ordinary facts,
because membership (a predicate over types) and order (facts about
class names) are separate planes and neither constrains the other.

**The five calls walk the diamond.** `int16` lands at the bottom;
`int64` is Signed but not Small; `uint16` is Small but not Signed —
the two incomparable middles, separated only by which predicates the
argument answers; `float64` reaches only Numeric; a string reaches only
the bare method.

**Transitivity is not authored here, and is not needed here.** See
`tests/lattice_gap` for why that holds only while the middle classes
carry methods of their own.
