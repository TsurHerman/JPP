# A caller supplies the missing comparison

The library is the same as [lattice_gap](../lattice_gap/test.md): its Tiny and
Numeric methods overlap, and its Tiny→Small→Numeric chain provides no direct
comparison between those two candidates.

The caller imports `bridge.jpp`, which contributes one ordinary method:

```jpp
using preds
export <:

<:(Tiny, Numeric) = true
```

That direct edge selects the Tiny method. `gap(itsy())` must return its marker,
10, without changes to the library's methods or predicates.

The promise is caller-authored ordering across module boundaries. The compiler
still performs no transitive closure; the caller wrote the exact missing pair.
