# Generality: packs, types, and ordinary generic libraries

Status: **implementation plan — proposed sequencing, not new ratification.**
Prepared against `4428ce6` on 2026-09-11. The last validated baseline has
58 language cases, including 19 compile rejections and 6 frontend rejections,
plus 20 machinery tests and 25 probe tests. This document changes no compiler
behavior. Existing ratified semantics remain binding; recommendations below
identify the choices needed where the ledger is still OPEN.

## Intended result

Make it possible to write reusable libraries over heterogeneous values,
variable argument counts, named inputs, and user-defined type families.
Keep testing the result in real module trees:

- Evolve checkout from a fixed pair of identically typed lines to a tuple
  of physical and digital lines, with explicit named quote fields and the
  same deep member-policy overrides.
- Add a small numerical library whose typed vectors, mixed numeric inputs,
  promotion rules, and reductions are ordinary jpp definitions.

For type “hierarchies,” build families such as `Signed`, `Integer`, `Float`,
and `Real` through ordinary predicates and authored order facts. Membership,
type identity, dispatch preference, and conversion remain distinct questions.
An order edge does not prove membership inclusion or authorize a conversion.

The implementation order is:

**tuple/pack values → named arguments → varargs/forwarding → static values
and type application → type families/records → numeric promotion → integration.**

Each stage lands with its own executable promises and a useful application
change. Avoid a large parser rewrite before the first usable feature.

## What exists, and what actually needs work

| Area | Current evidence | Missing work |
|---|---|---|
| Named argument binding | `src/jpp.zig` has named slots and routes raw fields by name; `binderprobe.zig` checks no cross-fill and bound-instance convergence. | Surface syntax and ANF argument labels; compare named constraints by field name rather than declaration index. |
| Varargs | Ratified grammar and unused intended AST describe rest inputs. | Active binder requires `raw field count == signature length`; active slots and rank policy do not implement rest inputs. |
| Tuples and records | Ground-returned records, static type fields, and immutable aliases RUN. | Surface construction, projection/destructuring, splatting, and pack-building operations. Active ANF operations are calls only. |
| Type-valued calls | Exact type values, type-returning calls, and bound return types RUN. | General static selector values: `ValueInfo` currently retains an actual value only when that value is a type. |
| Parametric families | `vecprobe.zig` checks selector extraction, repeated bindings, re-application, and forged-stamp rejection for its Vector constructor. | Surface applications, application of computed type values, constructor protocol, and pattern integration into dispatch. |
| Mixed numerics | Design sketches and the historical hand-transpiled spike show promotion; current Base has exact int64/float64 methods. | An ordinary promotion/conversion library in the active pipeline. `base_mixed` intentionally rejects mixed inputs today. |

`src/ast.zig` is not an implementation to copy unchanged: its comments still
describe summed ranks and two separate packs, contrary to the current ledger.
Update that model as the active representation evolves. Preserve one semantic
pack carrying positional fields, named fields, and actual static values.

## 1. Tuple values and pack construction

Add a shared representation of argument entries and structural value
construction to the active parser, normalizer, and comptime interpreter.
Keep labels, source evaluation order, and splat boundaries until the
machinery can construct the actual pack. jppc remains file-local and
context-blind; it must not guess argument types or resolve a splat's arity.

Proposed initial spellings:

```text
empty = ()
single = (x,)
pair = (x, y)
fields = (; cents = 100, grams = 250)
```

The empty tuple and splat meaning are ratified. Confirm singleton and named
record spellings in the first implementation slice. Parenthesized `x` remains
grouping. A tuple may mix values, types, and element types without promoting
its contents. Add ordinary tuple operations for length, first element, tail,
and field access, using minimal grounds for native representation boundaries.

Construction must evaluate each producer once in written order. Reordering
named storage or normalizing a pack may route completed results, but must
never reorder their effects. Recommend name-based identity for structural
named records, with an explicitly documented canonical layout; a method's
bound call pack still follows its declared parameter order.

Tests: `tuple_values`, `tuple_types`, `tuple_effects`, `tuple_empty`, and
negative malformed tuple/projection cases. Distinguish an empty tuple from
`nothing`, a singleton from grouping, and a tuple argument from several
arguments. In checkout, replace the two-field basket storage with tuple
storage while keeping its two-line public entry point initially.

## 2. Required named arguments

Expose the already-ratified two-section calling convention:

```text
scale(x; factor::float64) = x * factor
scale(3.0; factor = 2.0)
```

Positionals bind only positional slots; names bind only named slots. Named
argument types participate in dispatch. The implementation must extend the
normalizer's current unlabelled argument array and route values using the
same mapping that proved the candidate applicable.

Before enabling overloads, fix specificity's coordinate system: align
positionals by position and named constraints by name, even when two method
declarations list their named parameters in different orders. Preserve
pointwise dominance, module-position ties, and ambiguity among competing
maxima in the winning module. Canonicalize the selected bound pack without
changing call-site evaluation order.

Required keywords first. Defaults remain OPEN and are a follow-on decision:
their evaluation context, timing, and effect on candidate applicability need
explicit rules. Do not encode absence as a dummy argument or let a default
silently select a different method.

Tests: `named_arguments`, `named_permutation`, `named_specificity`,
`named_context`, plus missing/unknown/duplicate names, crossing constraints,
and both directions of forbidden positional/named cross-fill. Retain the
probe's instance-convergence check at machinery level. In checkout, give
`quoteRecord` six named fields so swapping tax and freight is visibly wrong.

## 3. Varargs and forwarding

Expose a positional rest input that binds one tuple, and its call-side
inverse:

```text
collect(items...) = items
forward(items...) = target(items...)
```

Start with one trailing rest input in the positional section, before any
named section. Then add named-rest capture/forwarding using a record after
`;`, with duplicate names rejected. Retain fixed positional prefixes and
required named inputs. Decide the exact named-rest spelling with its tests.

Extend construction to return enough routing information for both fixed
fields and the captured remainder. Compute specificity on the actual call's
coordinates: a fixed slot and a rest-covered slot may correspond to the
same argument even when declaration lengths differ. Preserve the ratified
fixed-versus-variadic ladder and pointwise comparison; settle typed-rest and
zero-length-tail ties explicitly rather than inventing a summed rest rank.

A heterogeneous rest tuple is distinct from a tail whose elements must
share one bound type. Define those constraints explicitly and test the empty
tail, where an element type cannot be inferred without another witness.

Add reductions with zero/one/many base cases and recursion on a strictly
shorter tuple. The domain owns its empty identity; do not assume every
generic sum returns integer zero. Keep each step an ordinary jpp call so
caller arithmetic remains effective. Measure 0, 1, 2, 8, and 32-element cases
to expose specialization growth and the known comptime recursion risk.

Tests: `varargs`, `varargs_specificity`, `varargs_types`, `splat_forward`,
`named_rest`, `tuple_reduce`; negative duplicate fields, invalid splats,
unbound empty-tail types, and overlapping rest signatures. Evolve checkout
to zero, one, and many heterogeneous line items in two fresh contexts.
These are statically shaped packs; runtime-length collections remain a
separate feature.

## 4. Static values and application of types

Generalize static value preservation beyond `type` so a family can depend
on dimensions, enum selectors, or other genuinely comptime data. Keep
ordinary runtime values out of instance keys; supplying data to a call must
not accidentally specialize on its value. All-comptime calculations that
produce a type must retain enough intermediate information to evaluate it.

Expose brace syntax as the ratified emphasis for leading static arguments,
using the same word and semantic pack as paren application. Test convergence
when both spellings supply the same static pack; do not introduce separate
`promote{}` and `promote()` method tables. Reject a runtime-derived dimension
when a type construction requires a static one. Closed-domain runtime
selector bridging is a later extension, not a prerequisite for static
type-family use.

The active callee is a string. Add application of a known word/type value
without confusing a local alias with a new global spelling. Make the
constructor protocol explicit so `V = Vector{float64, 3}; V(values)` works
through the ordinary call model. General closures can follow separately.

Tests: `static_values`, `brace_paren_identity`, `type_application`,
`constructor_alias`, and runtime-selector rejection. Cover literal and
computed static dimensions, static values travelling through tuples and
named packs, and distinct runtime data sharing an instance.

## 5. Type families, records, and relationships

Implement supported parametric patterns such as `Vector{T, N}` using
explicit selector metadata and re-application checks, extending the probe
into the active binder. Repetition means identity/unification; an authored
mutual order relation still does not make two concrete types identical.
Do not treat arbitrary type-returning functions as invertible constructors.

Bring immutable named records into the surface over this mechanism. Choose
their declaration spelling and distinguish structural record values from
nominal user-defined families. Require field names/types to be defined or
bound, validate construction, and keep field access and constructors
inspectable. New mutable state or inheritance-driven storage layout is
outside this slice.

Use ordinary predicates to define overlapping families, joins/intersections,
and domain categories. Keep pairwise `<:` facts explicit. Add examples where
membership overlaps without an order edge, and where an order preference
does not prove membership inclusion. Existing `lattice_gap`, `pointwise_gap`,
and class-name rejection tests remain essential boundaries.

Tests: `parametric_family`, `parametric_unification`, `family_provenance`,
`record_construction`, `predicate_families`; reject forged selector metadata,
mismatched dimensions, undefined family names, and missing/extra fields.
Replace checkout's ground-only domain record declarations with this surface.

## 6. Mixed numeric types through library promotion

Build explicit numeric modules with concrete arithmetic grounds, predicates,
`convert`, and `promote`. Start with a finite supported matrix, for example
int32/int64 and float32/float64, and verify both values and resulting types.
Add signed/unsigned pairs as a subsequent table with explicit overflow and
inexact-conversion behavior, following the ledger's Julia-oriented decisions.

Same-type calls reach exact methods. Mixed methods visibly choose a common
type, convert both values, and call the operation again. Binding itself
never casts. The binary promotion rule owns the two-input case; the variadic
reduction must not capture an unsupported binary pair and recurse forever.

Keep this richer numeric module explicitly imported initially. That leaves
the deliberately small Base and `base_mixed` promise intact. A later expansion
of implicit Base is a separate interface decision. Cross-check every declared
promotion pair rather than deriving conversion rules from the authored order.

Tests: `numeric_promote`, `numeric_convert`, `numeric_variadic`,
`numeric_context`; rejection cases for a missing pair, inexact conversion,
and conflicting promotion methods. Test caller overrides reaching through a
generic numerical library, with inferred return types following the selected
promotion rule. Use a fixed and documented fold order; arbitrary custom
promotion rules need not be associative.

## 7. Demonstrate the combination and close the loop

Keep checkout as the domain case and add a numerical module tree: vectors,
scalar promotion, reductions, and a caller policy. A mixed-element dot product
should share a dimension binder while permitting different element types;
incompatible dimensions must fail. Exercise named options and pack forwarding
through multiple modules, not only direct root calls.

At each stage:

1. Add a `tests/<case>/test.md` describing the observable promise.
2. Add positive programs with `using Test` and `check`, and the relevant
   `expect.err` or `expect.transpile.err` rejection cases.
3. Reuse separate root programs for context contrasts. Include composed
   cases involving gates, private helpers, imported order, and collapse.
4. Run `zig build test`; run demo/probes for the changed paths. Preserve
   prior negative promises unless the explicitly chosen feature changes
   that promise, then document the replacement coverage.
5. Record verified RUNS status and remaining limits, and commit/push each
   coherent stage. Measure representative compilation cost rather than
   treating a successful tiny example as evidence of scalability.

Callable dependency contracts remain a parallel design question, documented
in [word_contracts.md](word_contracts.md). Every new example should use real
source-visible definitions/imports; avoid inventing undeclared extension
points to make generic forwarding appear complete. This plan also leaves
runtime collections, memory ownership, hot swapping, and full compiler
bootstrapping for later work.

## First implementation slice

Begin with tuple values, shared pack-entry metadata, and required named
arguments. The reviewable result is a checkout quote assembled by named
fields plus focused tests for tuple identity, effects, named dispatch,
and forbidden cross-fill. After that passes, use the same representation
for varargs rather than building a second argument system.
