# Compose predicates with ordinary boolean functions

A library can define an input group by combining existing predicates:

```jpp
Integer(T::type)::bool = Signed(T) || Unsigned(T)
SmallSigned(T::type)::bool = Signed(T) && Small(T)
```

The first accepts either signed or unsigned integer types. The second requires
both signedness and a width of at most 16 bits. The `kind` methods use these
named predicates as ordinary signature gates.

| Input type | Selected rule | Result marker |
|---|---|---:|
| uint8 | Integer | 1 |
| int8 | SmallSigned | 3 |
| int64 | Signed | 2 |
| float64 | Any fallback | 0 |

`order.jpp` explicitly authors the priorities between the predicate words.
Even when containment is obvious from their bodies, the compiler does not
prove an order from it.

`||` and `&&` are ordinary exported functions defined over bool in `preds.jpp`.
The parser supplies infix spelling and precedence. The `Prec` probe checks
that `Signed(T) && Unsigned(T) || Unsigned(T)` means `(A && B) || B`: it must
be true for an unsigned type. The other grouping would be false.

Type variables bound in signatures may be passed into predicate bodies;
`type_bindings` checks that scope. This case uses explicit type-valued inputs
to make each membership question visible.
