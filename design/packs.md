# One pack for calls, data, and specialization

Status: RUNS for tuples, named inputs, and static-field preservation — verified by
the complete suite on 2026-09-12. Varargs rules below are RATIFIED for the next
slice and have no active syntax yet.

## Values and calls

| Spelling | Meaning |
|---|---|
| `(x)` | Grouping |
| `()` | Empty pack; distinct from nothing |
| `(x,)` | One positional field |
| `(x, y)` | Two positional fields, possibly different types |
| `(; tax = x, freight = y)` | Named structural value |
| `(x; label = y)` | Positional prefix plus named section |
| `f(x; factor = y)` | Apply f to that two-section call pack |
| `f(x; factor::float64) = ...` | Required named input, participating in dispatch |
| `value.0`, `value.tax` | Static positional/name projection |

A tuple does not promote its elements. Named value identity depends on field
names, types, and static values, independent of written field order. Positionals
retain order. Named storage uses sorted field names; a selected method's bound
pack uses its own declaration order. Neither rule specifies a portable C ABI.

Expressions evaluate once in source order before their results are routed.
Local bindings name those results; projection and permutation do not rerun
producers. `Base.Tuple` defines ordinary len, first and tail operations. len and
tail require positional tuples; tail of a singleton is empty, tail of empty
fails. first projects positional field zero, which must exist.

## What is static

| Field source | Preserved in specialization identity? |
|---|---|
| Ordinary integer/float/bool/string source literal | Its type, not its value |
| Ordinary runtime parameter or call result | Its type, not its value |
| A type value | Both its kind and actual type identity |
| An explicitly comptime native field | Both its type and actual value |
| Projection/identity/packing of such a static field | The same static value |
| General arithmetic on non-type static inputs | Not yet evaluated as static |

Static availability is a semantic property, not a compiler optimizer's guess.
Numeric literals do not become static selectors merely because their source is
constant. Native pack producers must use runtime fields for ordinary data;
Zig's anonymous literals can intentionally describe comptime fields. Static
fields require no runtime storage but still participate in type identity.

A call returning a static field can have preceding runtime effects. Retaining
its result never authorizes deleting those effects. Calls producing type values
remain comptime-only and cannot depend on runtime state.

Brace application and more general static evaluation are later work. They must
use this same pack and method table, preserve static values during forwarding,
and reject runtime-derived dimensions where a type requires a static selector.

## Matching and preference

Positionals bind by index, names by name, with no cross-fill. Required slots
must be present, unknown names do not match, and duplicate named fields are a
frontend error. Defaults and rest capture are not part of this slice.

Specificity compares the same call coordinates. Reordering named declarations
must not pair a constraint on tax with one on freight. Exact/predicate/bare
ranks, authored pairwise order, and conjunction witnesses retain their existing
meaning. Crossing constraints need an intersection or remain ambiguous in one
winning module/unit. Repeated type binders, including an explicit type-value
witness, require identity.

Keyword permutation and changed runtime data reuse a bound method instance.
Different static values can select different instances. Tests must observe this
at the bound method, rather than mistaking a call-site wrapper for its body.

## Decisions for the varargs slice

A rest input captures a tuple; call-side splat is its inverse. Statically shaped
packs come first; runtime-length arrays are a separate memory/iteration feature.
Compare supplied coordinates pointwise. Fixed coverage outranks rest coverage;
within two rest-covered coordinates, compare their element constraints using
the ordinary ladder and authored order. Never sum ranks over a tail.

When all supplied coordinates tie, a strictly narrower accepted pack shape can
break the tie: fixed empty shape precedes an unconstrained rest. Shape comparison
is structural (arity and required labels), not a proof about predicates. It
cannot repair an incomparable argument coordinate.

| Overlap | Decision |
|---|---|
| Fixed zero-input method vs unconstrained rest, at zero arguments | Fixed empty shape wins |
| Fixed slot vs typed rest covering the same argument | Fixed coverage wins |
| Two rests with different element constraints and actual elements | Compare each supplied element |
| Typed int rest vs typed float rest, both empty | No element witness; ambiguous in one unit |
| Uniform bound-T rest, empty and with no other T witness | Does not match: T is unbound |
| Named constraints cross in quality | Neither compensates for the other |
| Two identical named sets in different declaration orders | Same coordinates; order supplies no preference |

Implement this table with positive and negative cases before enabling varargs.
A reduction needs explicit zero/one/many domains and shrinking recursion; an
unsupported binary pair must not fall into a self-repeating variadic fallback.
