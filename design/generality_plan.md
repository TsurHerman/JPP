# Generality implementation sequence

Revised 2026-09-20 after implementing value qualifiers and native error dispatch.
The modular DWARF reader remains the first binary consumer. This supersedes
the earlier feature-by-feature sequence, which postponed dependency visibility
and static fields until after consumers were already built.

The purpose is reusable libraries and inspectable binary units, exercised in
real module trees. Membership, identity, preference, and conversion remain
distinct. Keep caller-first context, pointwise dominance, and explicit pairwise
order. The active compiler and tests determine RUNS status.

## Current steering recommendation

This section is the proposed near-term direction; the dated sections below retain
the implementation ledger. Keep Zig as the compiler host and provider of native
types, code generation and useful library implementations. Define jpp's public
semantics through its own contracts: context, identity, cases, packs and refinement.
A foreign representation can implement those contracts without determining every
source-language rule. In particular, using Zig enum/union metadata does not choose
jpp's collection, ownership or declaration model.

The first source milestone is now the [working DWARF reader](dispatch_tables.md#the-working-use-case-reading-dwarf-offsets),
chosen in place of the abstract comparison/accepts sketch. Separate jpp modules
choose width and byte order from real Zig enums, and their ordinary calls compose
the switches. Tests cover the four runtime combinations, static type selection,
errors, evaluation order and a caller's override inside the binary reader.

Base.Zig supplies an ordinary native namespace value. Module constants and enum
member-path patterns retain their lexical native identities through module
composition. This completes the bounded source slice, not a general reflection
or branch library. Next specify ordinary static application's stage/context and
derive the remaining generic primitives from this consumer. Arbitrary initializer
calls, callable values and staged branch continuations remain unbuilt.

The next bounded slice now runs: [log labels](../tests/log_labels/test.md) uses
ordinary boolean predicates and classifier comparisons in `where`; typed defaults
complete the enum table. A [file-header reader](../tests/error_dispatch/test.md)
uses native finite error sets and error unions through the same dispatch path,
including a validator that adds an error and a caller that replaces one message.
[Packet routing](../tests/value_guard_variant/test.md) uses the known type/tag of
a native sum value while preserving its runtime payload.

These guards refine one fixed argument at a time and execute only from known
facts. Their dependencies remain lexical, their applicability remains contextual,
and overlapping predicates need normal precedence. `isOneOf(value, cases...)`
is a variadic membership query. First-class predicate factories, correlated
multi-input guards, runtime numeric intervals and arbitrary static initializers
remain separate work. Native error-set/union result joins now run; unrelated
successful result types do not silently acquire a new sum representation.

A port earns its place when ordinary jpp definitions make shared behavior or
contextual customization useful and can be checked against the native reference.
Port those algorithm bodies while retaining suitable Zig leaves. A wrapper
around a Zig std function does not make calls inside that function overridable:
grounds receive no caller context. The desired extension points must be actual
jpp calls. Rewriting the whole standard library is not the next milestone.

Overridable `=` for both bindings and method definitions is an agreed eventual
direction. Preserve room for it while completing this slice; building its staged
definition engine immediately would turn the scalar milestone into a compiler
bootstrap project. Runtime collections, memory policy and a general value-guard
solver likewise have no role in this scalar binary-reader proof.

## 1. Foundations

RUNS — verified 2026-09-12:

- An export without a body declares a word and supplies no dispatch candidate.
  Check calls and gates in every source body against real local/imported/exported
  declarations. A caller cannot introduce a missing source name.
- Explicit folder imports recursively collect public exports. Base is the
  namespace root; Base.Arithmetic, Base.Any, Base.Test and Base.Tuple are leaves.
  Remove hidden imports; optional same-name facades select package exports,
  while Folder.* explicitly imports siblings excluding the facade.
- Mutual imports form one dispatch/compilation unit. Private definitions remain
  file-local. Public candidates share one unit position; same-unit ambiguity
  cannot depend on which member was imported first.
- Specify static fields before extending packs: their values participate in
  specialization, ordinary runtime fields contribute only their types. Preserve
  static fields through projection and forwarding without deleting effects.
- Settle current named-field comparison and the next varargs decision table in
  [packs.md](packs.md). The next section records rest implementation.

Evidence: declaration_tunnel, override, undeclared_call, undeclared_unused_call,
undeclared_gate, undefined_export, base_folder, folder_modules, folder_collision,
Base shadowing cases, unit cases, and pack_static. Full typed contracts remain
OPEN; name availability is not a universal implementation-coverage proof.

## 2. Tuples and required named arguments

RUNS — verified 2026-09-12:

- Tuple, named-record, and mixed pack values share a representation with calls.
  Grouping, empty, singleton, heterogeneous values, and named identity are explicit.
- Static positional and named projections; ordinary Tuple utilities.
- Required named inputs bind by name and participate in dispatch, without
  cross-fill. Defaults remain unbuilt; the next slice adds splats and rest capture.
- Preserve source evaluation order while canonicalizing value identity and bound
  method instances. Compare matching coordinates across declaration permutations.
- Checkout uses tuple basket storage, named quote construction, and surface field
  access. The varargs slice below expands its original two-line basket contract.

Evidence: pack_values, pack_static, named_arguments, named_specificity,
named_context, named_instances, type-witness mismatch and malformed pack cases,
and the existing checkout receipts under two fresh caller contexts.

The build must regenerate source trees and rerun negative compilation checks;
a cached process result for an old generated file is not fresh validation.

Verification on 2026-09-12: `zig build test demo probes --summary all` passed
all 246 build steps, covering 97 language cases (including 41 expected compile
rejections and 11 expected frontend rejections) and 45 machinery/probe tests.
`zig test src/ast.zig` passed all three AST tests. The obsolete emitter and
hand-transpiled demos were subsequently removed; the research probes remain.

## 3. Varargs and forwarding

RUNS — verified 2026-09-12:

- One trailing positional rest and one trailing named rest; call-side and
  pack-value splats with section and duplicate-name checks.
- Pointwise comparison of actual supplied coordinates; fixed coverage before
  rest, then element constraints. Structural shape breaks tied coordinates.
- Uniform T rests require a witness even when empty; short predicate annotations
  check each captured element independently. Static fields survive forwarding.
- `varargs_scale` exercises shrinking reductions at 0, 1, 2, 8 and 32 elements.
  `varargs_binary_gap` rejects a missing binary implementation without recursion.
- Checkout now has zero/one/many heterogeneous physical and digital lines,
  independently defined record types, recursive pricing, and unchanged caller
  policies. Digital-only carts incur no freight.
- `varargs_forward` uses multiline library parameters, calls and a block body;
  main has no special grammar. Forwarding preserves effects and bound identity.

Verification: `zig build test demo probes --summary all` passed all 291 build
steps: 119 language cases (56 expected compile rejections and 14 frontend
rejections) and 48 machinery/probe tests. `zig test src/ast.zig` passed all three
AST tests. Checkout checks 20 baskets through 20 source modules and 161 assertions.
The final type-witness regression also corrected native-body lookup: T denotes
the element type, including an explicit empty-rest witness, rather than the
captured tuple's type.

Local compilation sample (2026-09-12, Zig 0.16.0, Darwin arm64):
each arity uses an isolated source tree containing the reduction and forwarding
modules plus one root program from `tests/varargs_scale`. Times are one wall-clock
sample per size with a shared warm Zig cache, using `zig build-exe -ODebug`.
Each produced executable ran and checked its sum. Debug sizes include metadata;
these are not sealed-build size estimates.

| Arguments | Transpile (s) | Zig compile (s) | Debug binary (KiB) |
|---:|---:|---:|---:|
| 0 | 0.467 | 0.988 | 1868.4 |
| 1 | 0.016 | 0.972 | 1868.9 |
| 2 | 0.016 | 0.978 | 1870.1 |
| 8 | 0.017 | 1.183 | 1897.3 |
| 32 | 0.018 | 4.016 | 2080.3 |

Process startup and filesystem work are included. These single local samples
show that the 32-element reduction compiles and terminates; they do not establish
a general scaling law for deeper module graphs or runtime-sized collections.

Runtime-sized collections and keyword defaults remain separate work.

## 4. Static computation and callable types

Generalize static calculations, expose brace application with the same semantic
pack and word table, and reject unavailable runtime selectors. Constructor aliases
and known callable values need dependency discovery and private-home preservation
before context collapse. Test deep caller overrides through an alias.

Compare literal/computed static selectors, keyword permutations, and different
runtime data at the bound method's instance identity. General closures and
bool/integer-range bridges remain later extensions. The enum/tagged-union
bridge below was brought forward to test declarative library composition.

### 4a. Injected tables through a real library

RUNS — verified 2026-09-15.
This bounded increment was brought forward at the user's request. Ordinary
calls inject enum/tagged-union switches before method selection. Each arm uses
the active resolver. Known tags select one arm; runtime tags require coverage
of all arms. Tagged payloads use the agreed Variant(owner, tag) value with
.payload; predicates group variants. Same-owner returned variants rejoin their
union; arbitrary return joins remain unbuilt.

The [JSON case study](dispatch_tables.md#earlier-source-problem-json) uses std.json.Value directly. Its
jpp layer factors scalar and container behavior, traverses runtime-sized data,
and composes two independent policies over enum-and-writer regions. Its Zig
collections are foreign fixture details. Expansion and large-array experiments
are paused; the recursive walk does not establish a memory or iteration model.

Verification: `zig build test demo probes --summary all` passed all 309 build
steps: 127 language cases (62 expected compile rejections, 14 frontend rejections)
and 52 machinery/probe tests. The JSON case has 38 assertions in two programs;
variant_dispatch adds nine focused checks. The first full run exposed a case-
sensitive expected-diagnostic typo in the new crossing fixture; it was corrected
to the resolver's existing AMBIGUOUS diagnostic and the full run passed.

A separate ReleaseSafe build of the JSON case ran the same 38 assertions. On
this Darwin arm64/Zig 0.16.0 host, one wall-clock sample with a shared warm cache
and LLVM IR emission took 11.44 s; the executable was 572,552 bytes. It includes
the parser, reference serializer, both contexts and test harness, so this is not
a standalone library-size estimate. Inspection of the optimized LLVM IR found
an eight-arm integer switch inside a jpp call implementation. The static-only
positive fixture separately demonstrates selected-arm coverage and type results.
No general compile-time or stack-scaling claim follows from this sample.

### 4b. Scalar cases and partial evaluation

Historical proposal, superseded as the first consumer by the DWARF reader above.
OPEN research sequence, not new syntax or
ratified runtime-predicate semantics. The [dispatch notebook](dispatch_tables.md)
separates method regions, knowledge established by a branch, and residual control
flow. The existing small integer-range probe enumerates values; symbolic interval
refinement needs a different mechanism.

First expose already defined case values and exact patterns in source, then use
Zig's Order.compare as an 18-cell modular example. Follow it with numeric
compare(a, op, b), exercising both known and runtime operators with integer and
float data. NaN exposes the limit of a three-outcome relation: negating greater
does not implement less-or-equal for arbitrary floats. Keep comparison equations
in authored library definitions and preserve context semantics.

Only after that evidence, design the smallest staged branch/refinement primitive
and its library boundary. This keeps arrays, ownership and traversal out of the
dispatch proof. Reflection, callable application and general value-guard overlap
remain explicit gaps; the notebook lists the proposed tests and decision limits.

Progress, 2026-09-18: member expressions on known enum types RUN. Both
`orderType().lt` and projection through a local type alias retain a static enum
value. The enum_members case covers ownership and forwarding; two rejection
cases cover missing members and non-enum owners. Declarations and signature
patterns remain unbuilt. Dedicated enum declarations are no longer assumed to
be the next step; the surface may keep representation categories opaque.

Progress, 2026-09-20: module constants and exact enum member paths in signatures
now RUN (`static_bindings`, `dwarf_offsets`). Generic native member access also
exposes namespaces/public constant declarations. Initializers are bounded to
values/member paths or explicit grounds; general static application remains OPEN.

### Opaque representations, explicit capabilities

OPEN research direction, 2026-09-18, narrowed by the 2026-09-19 enum decision:
the enum interface is a tight Zig wrapper authored in jpp. Source programs may
use ordinary constructors, predicates and dispatch without separate enum/struct
declaration syntax. Existing
native enum recognition does not establish that enums must be a primitive source
declaration category. Types remain real values with identity; opacity concerns
how their representation and capabilities are exposed.

An injected switch still requires facts: what alternatives are possible, how to
select an alternative at runtime, and what that selection establishes about the
input. Comptime library operations could supply this information. The current
bridge uses Zig reflection directly; an authored protocol has not been designed
or implemented. Exhaustiveness requires a closed set of alternatives or an
explicit remaining case, not an assumption that an arbitrary predicate family
is closed. Nothing here adds automatic traversal of fields hidden in records.

The next source experiment should expose case values through ordinary words and
study general static value patterns before adding category-specific declarations.
Computation of a case value in a signature still needs an explicit stage and
context rule. This preserves the comparison example while avoiding a premature
enum-only definition mechanism.

### Definition as a dispatched operation

RATIFIED direction, 2026-09-18: `=` should eventually be an overridable function
call covering both value bindings and method definitions. Current local bindings
remain immutable aliases and the compiler still reads method definitions directly.

The agreed model dispatches on a definition target and a scoped, unevaluated
right-hand side. `f(x) = x + 1` cannot eagerly call f or evaluate its body before
x is bound. Likewise, a fresh binding name on the left cannot be looked up as an
already existing value. Scope, source identity and evaluation stage must be
represented explicitly if ordinary dispatch is to supply definition behavior.

An overridable definition operation can still produce a stable named type.
Fixed resulting identity and overridable construction are compatible. Therefore
`Order = enum { ... }` versus a type-returning function is not a choice between
permanently primitive bindings and extensible computation. Avoid an enum-specific
definition rule that forecloses a general protocol.

Open decisions: the detailed target/body representation; which compilation context
selects a handler; how a handler elaborates or evaluates its right-hand side; and
the minimal bootstrap mechanism that defines the first `=` methods. The default
binding handler can evaluate once and introduce an immutable name. No overload
may be assumed to change evaluation count or name visibility until those rules
are specified. Supporting the shared enum-member expression does not settle them.

## 5. Independent library increments

Develop [type families](type_families.md) and [mixed arithmetic](numerics.md)
as separate increments; neither needs to wait for every feature in the other.
Ordinary predicate families can grow throughout all stages.

Type families need supported selector patterns, repeated identity constraints,
re-application provenance, and explicit nominal-record construction. Anonymous
structural values must keep their existing identity rules.

Numerics need a finite promotion/conversion matrix and explicit failure behavior.
Resolve the exact-conversion policy before copying any ground implementation.
Add expected runtime-failure support before testing value-dependent conversion
errors. Keep richer arithmetic explicitly imported initially.

## 6. Integration and binary interface evidence

Add a numerical module tree with mixed-element vectors and dot products sharing
a dimension binder. Exercise named options, forwarding, predicates, private
helpers, and caller policies through several modules. Mismatched dimensions and
missing implementations must diagnose the actual boundary.

At every implementation milestone: add meaningful test.md promises and positive/
negative programs, run zig build test, demo and affected probes, update verified
status, then commit and push. Measure representative compilation cost. Binary
artifact loading, hot replacement, ownership and compiler bootstrapping remain
future work described in [binary_units.md](binary_units.md).
