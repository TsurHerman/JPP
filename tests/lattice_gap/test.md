# An authored chain does not fill a missing comparison

The library declares `Tiny <: Small` and `Small <: Numeric`, but defines `gap`
methods only for Tiny and Numeric. The int8 sample satisfies both methods.

The compiler compares the actual candidates directly: it asks whether
`Tiny <: Numeric` or `Numeric <: Tiny` was authored. Neither was. Both methods
remain maximal in the same module, so compilation must report ambiguity.

Small has no method here. Its ordering edges cannot eliminate either candidate.
This is why [lattice](../lattice/test.md) can resolve its diamond while this
case fails: that case includes the intermediate methods.

The repair is one explicit edge:

```jpp
<:(Tiny, Numeric) = true
```

[lattice_bridge](../lattice_bridge/test.md) supplies it from the caller without
editing the library. This negative case keeps it absent. Making the test pass
by inferring transitive closure would violate the language's pairwise order.

If the competing methods lived in different modules, context position could
break their tie. They intentionally share one module here to require the
ambiguity diagnostic.
