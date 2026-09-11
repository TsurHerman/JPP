# order_variables

The order word takes actual type values. Defined/imported names constrain a
specific value; fresh names bind inputs, independent of capitalization.

```jpp
using preds
same(P::type, Q::type)::bool = zig{ P == Q }
<:(P::type, Q::type) = same(P, Q)
<:(Signed, Integer) = true
```

The general rule consumes both input variables. The specific fact refers to
existing predicates exported by `preds`. It refines the type-domain rule
(exact type value rank 4 versus input type rank 3), even though the general
rule is written first. Dispatch of the order uses the stratum-0 ladder, so
ranking these methods does not query the order being defined. `same` is a
private helper and its comparison is type identity, not order-derived equality.

An intentionally constant general rule would be written
`<:(::type, ::type) = false`; writing fresh named inputs and ignoring them
would be a declaration error.
