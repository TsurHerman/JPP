# One pack for calls, data, and specialization

Status: RUNS for tuples, named inputs, rest capture, splats, and static-field
preservation — verified by the complete suite on 2026-09-12. See the
[implementation plan](generality_plan.md) for validation and compilation costs.

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
| `f(xs...; opts...) = ...` | Positional tuple rest and named record rest |
| `f(prefix, xs...; label = value, opts...)` | Expand statically shaped packs into their own sections |
| `(prefix, xs...)`, `(; label = value, opts...)` | The same expansion constructs data packs |

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
must be present; unknown names require a named rest. Duplicate explicit names
are frontend errors; duplicates introduced by splats fail during expansion.
Defaults remain unbuilt. Each section permits one trailing rest. Splats accept
only fields belonging to their written section and never overwrite a field.

Specificity compares the same call coordinates. Reordering named declarations
must not pair a constraint on tax with one on freight. Exact/predicate/bare
ranks, authored pairwise order, and conjunction witnesses retain their existing
meaning. Crossing constraints need an intersection or remain ambiguous in one
winning module/unit. Repeated type binders, including an explicit type-value
witness, require identity.

Keyword permutation and changed runtime data reuse a bound method instance.
Different static values can select different instances. Tests must observe this
at the bound method, rather than mistaking a call-site wrapper for its body.

## Varargs rules

A positional rest captures a tuple; a named rest captures a canonical named
record. Call-side splat is the inverse. Statically shaped
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

`varargs_dispatch` and the `varargs_*` rejection cases exercise this table.
`xs::T... where T` requires all captured elements to share T, across both
sections and any explicit witness. `xs<:Predicate...` checks each element
independently, permitting mixed types and vacuous empty capture. Captured static
fields retain their actual values through forwarding. `varargs_forward` also
proves multiline library bodies, parameter lists, and calls work like main.

The native signature ledger handles structural rest inclusion/intersection,
including the empty overlap of disjoint typed rests. Whole-signature ambiguity
lint remains conservative (`unknown`) for rest overlaps; actual calls resolve
using supplied coordinates and full method gates.

A reduction needs explicit zero/one/many domains and shrinking recursion; an
unsupported binary pair must not fall into a self-repeating variadic fallback.
