# Four predicates form a dispatch diamond

The predicates describe numeric types, small numeric types, signed integers,
and small signed integers. The authored order is a diamond:

```text
         Numeric
         /     \
      Small   Signed
         \     /
        SmallSigned
```

Every int16 satisfies all four predicates. Each predicate has its own `kind`
method, and the four authored edges leave SmallSigned as the sole winner.
Other inputs demonstrate the two incomparable middle rules and the fallback:

| Input type | Winning rule | Result marker |
|---|---|---:|
| int16 | SmallSigned | 4 |
| int64 | Signed | 3 |
| uint16 | Small | 2 |
| float64 | Numeric | 1 |
| string | Any | 0 |

The numbers identify the selected method. Base supplies the ordinary order
placing the four domain predicates ahead of Any.

There is deliberately no direct `SmallSigned <: Numeric` edge. This succeeds
because the middle methods eliminate Numeric before losing to SmallSigned.
No transitive edge is inferred. [lattice_gap](../lattice_gap/test.md) shows what
happens when an intermediate predicate has no method at the call.
