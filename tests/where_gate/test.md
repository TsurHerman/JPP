# Type predicates qualify a method

The long and short spellings ask the same membership question:

```jpp
describe(::T) where T <: Integer = 1
terse(<:Integer) = 1
```

`Integer` is an ordinary function taking a type and returning a boolean.
The compiler does not supply an integer class hierarchy.

The complete `describe` and `terse` tables have an Any fallback, integer and
float gates, and an exact `int64` method. Both spellings must choose the same
result:

| Argument | Winning constraint | Result marker |
|---|---|---:|
| `1` | Exact `int64` | 3 |
| `1.5` | Float predicate | 2 |
| `"hi"` | Any predicate | 0 |

The numbers identify methods. Exact input types outrank predicates. Base's
ordinary authored order places the specific predicates ahead of Any; Any is
not a compiler wildcard. `kindof` removes the exact int64 method to show the
Integer gate winning on its own.

`pairup(::T, ::T) where T <: Integer` checks two independent requirements:
both arguments have the same type, and that type is an integer. Two integers
pass. An integer and float fail identity; two floats fail membership.

`main.jpp` intentionally does not import `preds`. A gate uses caller context
followed by its declaration home's imports, so the library declares its own
dependency. The caller imports Any to supply the ordinary fallback order.
