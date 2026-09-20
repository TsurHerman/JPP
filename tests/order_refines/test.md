# Callers can choose between overlapping type predicates

`Wide` accepts integer types with at least 32 bits. `Signed` accepts signed
integer types. Neither contains the other:

| Type | Wide? | Signed? |
|---|---|---|
| uint32 | yes | no |
| int8 | no | yes |
| int64 | yes | yes |

The two `category` methods return markers identifying their rule:

```jpp
category(<:Wide) = 1
category(<:Signed) = 2
```

For the int64 input `1`, both match at the same predicate rank. The program
must state which has priority. `wide_wins.jpp` imports `<:(Wide, Signed) = true`
and gets 1. `signed_wins.jpp` imports the opposite edge and gets 2. The library
methods and the input are identical in both contexts.

These edges express the caller's priority, not a proved containment. Each order
module imports `preds`, so both names refer to defined predicate values. Removing
that import would turn them into unused fresh inputs; `undeclared_order` checks
that mistake.

The order is itself an ordinary word. Its own method selection uses the base
rank ladder without consulting `<:` again, avoiding recursive order queries.
