# tests/ — the language's promises, as executable claims

Each folder is a CASE: a complete jpp tree whose PROGRAMS validate
one language aspect. A program is a root module that defines `main`
(filename is free). Assertions run in the language: `using Base.Test` (or `using Base`) and
`check(name, got, want)` printing `ok <name>` / `FAIL <name>: got X
want Y`. Check names name the ASPECT, never the probe data.

Start with [log labels](log_labels/test.md) for grouped enum dispatch and typed
defaults, [file-header errors](error_dispatch/test.md) for success/error dispatch,
or [packet routing](value_guard_variant/test.md) for tagged-union guards. These
examples state the application problem and expected outcomes before explaining
the machinery. Small rejection cases deliberately fail; their test.md names the
missing rule or invalid operation.

[Independent log records](enum_demand/test.md) shows where enum tables belong:
a generic coordinator keeps twelve levels runtime and invokes independent
classifiers. It does not enumerate their Cartesian product.

The [readability review](READABILITY.md) records the review of all 147 original
cases and the deliberate complexity retained in mathematical examples.

**Why more than one program?** `using` is the module's root context.
A nested call still accumulates, so two worlds cannot share one
`main` without leaking each other's imports. The harness starts a
fresh context at each program — libraries are shared files; worlds
are separate roots. Contrast cases (`override`, `depth_override`)
are two programs, same calls, different `using` lists.

**Self-judging, one artifact (unix):** jppc emits a single `run.zig`
per case. Each program runs under its own STATIC; failed checks
count themselves; a contrast case prints `[case/world] PASS|FAIL`
then `[case] PASS — N programs`. Exit 0/1. No separate judge, no
output oracle. `zig build lang-tests` walks `tests/` (no list to
edit) and trusts exit codes. Adding a case = one folder.

**Negative cases (error promises):** a case folder containing
`expect.err` never runs — the promise IS a compile error. jppc
transpiles it, then the harness compiles `run.zig` EXPECTING failure;
the file's content is the substring the error must contain. The
build step judges here (a program cannot self-judge its own refusal
to exist); compiling successfully FAILS the case.

**Frontend rejection cases:** `expect.transpile.err` instead requires jppc
to exit 1 with the specified substring. These cases test lexical syntax and
normalization errors before generated Zig exists. Use one failure-stage
marker per case; both stages are included in `zig build test`.

Cases: `dispatch` (selection + the specificity ladder, as values),
`caller_context` (generic arithmetic with explicit providers and explicit
Base imports), `override` (position shadowing through a library),
`depth_override` (surgical override through two
modules), `context_flip` (opposite orders, flipped winner),
`folder_modules` (facade, wildcard siblings, dotted addressing),
`where_gate` (predicate gates on `where`, the gated binder's rung, gate
composed with binder identity), `order_injection` (one `<:` fact cures a
gated clash — this folder is `where_gate_clash` plus a single line),
`order_refines` (the same edge injected from a separate module; reverse
it and the winner flips), `order_variables` (`<:` over variables ranging
over classes; a specific fact overrides a general rule by rank, not by
position), `lattice` (a diamond: one class below two incomparable
classes, which no single-inheritance tree can express), `lattice_bridge`
(the caller closes a gap in someone else's order with one fact),
`pred_join` (predicates defined as joins/meets of other predicates;
`||` and `&&` as ordinary words, and their precedence),
`ambiguity` (negative: same-module crossing errors at the call),
`where_gate_clash` (negative: overlapping gates, no edge declared),
`lattice_gap` (negative: an authored chain does NOT conduct across a
class with no method of its own),
`export_gate` (negative: an unexported word is invisible).

The declaration and type-value boundary cases are `declaration_names`,
`type_values`, `type_bindings`, `undeclared_order`, `unused_input`,
`unused_ground`, `unused_untyped_ground`, `unused_anonymous`, `any`, and
`unbound_where`. They separate lexical definitions from fresh variables,
allow unused annotated inputs while rejecting unused unannotated inputs
(including `_`), and preserve comptime type identity through binding and
calls. `order_type_only` and
`order_bool` reject invalid order queries/answers; `order_negative` checks
negative facts and context position. `pointwise_gap` rejects dominance with
an incomparable coordinate; `gate_conjunction` checks every conjunct.
`order_cycle` diagnoses a strict cycle with no maximum.
`collapse_dependencies` keeps a losing method needed for another decision.
`collapse_imports` keeps caller overrides needed behind deeper imports
without making those imports visible early. `ground_records` preserves runtime
data, static type fields, and runtime branch inference across ground boundaries.
`private_helpers`, `private_downstream`, and `folder_scope` test lexical
privacy and declaration homes through module aggregation. `equality_scope`
checks the same import rule for equality gates; `undefined_export` now proves that a declaration-only export does not invent
an implementation. The old rejection of all export-only words was superseded.

`Any` is an ordinary predicate from Base.Any, also exported by the Base facade. `any` checks direct calls, retained
types, predicate rank, and the authored Base order. `any_override` and
`any_shadow` check caller overrides and source-tree replacement;
`any_order_gap` and `any_unimported` reject hidden order and builtin names.

[checkout](checkout/test.md) is an application case study: twenty source
modules, twenty baskets in two contexts, and 161 assertions covering
discounts, rounding, delivery, tax, records, and accounting identities.
It uses explicit Base imports, immutable bindings, tuple basket storage, named
quote construction and surface field access. Domain imports and deep policy
overrides remain explicit. Rest capture now supports zero/one/many heterogeneous
physical and digital lines. Nominal record declarations remain unbuilt.

`base_import` compares explicit Base, caller overrides, import position,
and priority through deeper imports. `base_shadow` replaces the
foundation; `base_missing` and `base_mixed` reject hidden implementations and
implicit promotion. `module_encoding` keeps case, dotted-path, and underscore
identities distinct and prevents source modules from overwriting the runtime.

`local_bindings` tests evaluation once, effects in source order, aliases of
type and record values, discarded results, and nested blocks. Frontend cases
`binding_duplicate`, `binding_parameter`, `binding_type_parameter`,
`binding_forward`, `binding_self`, and `binding_call` pin the invalid forms.

## Promise catalog and coverage

| # | Promise (README ref) | Covered today | Boundary tests to write |
|---|---|---|---|
| 1 | Specificity ladder: exact type value > exact input type > pred > bare; dominance, never sum (§4, §9) | `type_values` (type value versus input type); `dispatch` (exact/predicate); `where_gate` (long and short predicate spellings, authored Any fallback); `any` (predicate above bare); `pointwise_gap`, `gate_conjunction`; machinery tests (bar lattice, full ladder) | — |
| 2 | Ambiguity: same-module crossing = comptime error at the call; intersection cures (§9) | `ambiguity`, `where_gate_clash`, `pointwise_gap`, `order_cycle` (negative cases); machinery tests | — |
| 3 | Ordered context: position breaks ties; flip flips (§1, §9) | `override`, `context_flip`; machinery tests | — |
| 4 | Context accumulation: caller ahead, callee STATIC behind (§1) | `depth_override`, `caller_context`, `equality_scope` | direct extendAll-ordering test |
| 5 | Depth overrides: surgical, unlimited (§1, §10.5) | `depth_override`, `collapse_imports`; `checkout` (4+ levels, discount and freight overrides at different depths) | recursive call graphs |
| 6 | Delegation `M.f` (§1) | machinery tests | surface `M.f` (parser) then a case |
| 7 | Collapse: resolving module owns the instance (§9) | `collapse_dependencies`, `collapse_imports`, `checkout`; machinery tests | symbol-hash stability once hashes land |
| 8 | Exports gate everything (§1) | `export_gate`, `private_downstream` (negative); `private_helpers`; machinery tests (fixture) | `M.f` qualification path once surface lands |
| 9 | The `<:` order word (§9) | `order_injection`, `order_refines`, `order_variables`, `order_negative`, `type_bindings`, `lattice` (diamond), `lattice_bridge` (caller closes a gap); machinery tests (7 ironing cases) | transitive closure: `lattice_gap` pins that there is none, and that the gap is an ambiguity |
| 16 | Operators are ordinary words: infix is surface only (§4) | `pred_join` (`\|\|`, `&&` and precedence); `value_equality` (`==`); `base_import`, `base_shadow`, `base_missing`, `base_mixed`; `checkout` (Base arithmetic); machinery tests (`+` shadowed) | more widths and promotion |
| 10 | Binder: packs, named args (§4) | named_arguments, named_specificity, named_context, named_instances; varargs, varargs_dispatch, varargs_forward; binderprobe | defaults |
| 11 | Demand-driven enum tables and injected variant tables (§4) | native resolver tests; enum_demand; variant_dispatch; variant_static; enum_members; dwarf_offsets; enum_pattern_*; json_dispatch; variant rejection cases, enum_open, enum_missing_member, enum_member_non_enum | arbitrary static pattern expressions; general result joins; optimal decisions for interacting inputs |
| 12 | Parametric type-words (§4) | vecprobe (spike) | surface braces |
| 13 | Folders are modules: facade, wildcard, dotted (§1) | folder_modules, folder_scope, cycle_folder, private_helpers | binary artifact boundaries |
| 14 | Tier invariance (§9) | — | needs tier infrastructure |
| 15 | Library resolution: modules from `Base/`, tree shadows Base | all check-based cases; `base_import`, `base_shadow`, `base_missing`, `any_shadow`, `module_encoding` | — |
| 17 | Defined signature names require lexical definitions/imports | `declaration_names`, `undeclared_order`, `undefined_export`, `static_bindings`, `enum_pattern_*` | general static application |
| 18 | Annotated inputs may be unused; anonymous universal predicate inputs use `<:Any` | `unused_ground`, `any` (positive); `unused_input`, `unused_untyped_ground`, `unused_anonymous` (negative) | richer pattern syntax |
| 19 | Type values and bound return types survive calls | `type_values`, `type_bindings`; machinery pack test | general static computation and braces |
| 20 | Every where variable must bind somewhere | `unbound_where` | arbitrary where expressions |
| 21 | Ground inference preserves runtime data and intentional static fields (§7) | `ground_records`; `checkout` (native record pipeline and void statement emission) | richer record surface |
| 22 | Immutable local bindings alias ANF values (§6) | `local_bindings`, `checkout`; `binding_*` frontend rejection cases | typed local annotations; application of callable values |
| 23 | Module constants and native member paths preserve lexical identity | `static_bindings`, `dwarf_offsets`; `static_binding_*` rejection cases | calls in static initializers; callable values |
| 24 | Value qualifiers use known branch facts, ordinary predicates and classifier comparisons | `log_labels`, `enum_guard_order`, `enum_guard_runtime_ambiguous`, `value_guard_variant`, `value_guard_static`, `value_guard_named_type`; guard rejection cases | runtime numeric intervals; correlated inputs; whole-rest guards |
| 25 | Native error sets/unions inject exhaustive tables and rejoin compatible results | `error_dispatch`; `error_*` rejection cases; native join tests | open anyerror dispatch; unrelated success-type joins |
| 26 | Equality and finite membership remain ordinary library words | `value_equality`, `log_labels`, `error_dispatch` | mixed numeric promotion; general record/collection equality; predicate factories |

`variant_static` preserves known results from static union arms through helpers,
named calls and rest forwarding. A returned known tag needs only its selected
method at the next call. Runtime effects execute once, while runtime payloads
remain data even alongside static coordinates.

`enum_members` selects defined members from known enum types, including through
type-returning calls and local aliases. Static values and enum owner identity
survive forwarding. `enum_missing_member` and `enum_member_non_enum` reject
undefined members and invalid owners.

`static_bindings` covers native namespaces/public constant members, module value
bindings, enum aliases, repeated fixed patterns, sparse native tags, lexical
declaration homes, forward value dependencies, facades, re-exports, identical
aggregate values and public import-cycle units. Its negative companions reject
private access, rebinding, value/method collisions, differing aggregate values,
value cycles, builtin replacement, calling constants and unstaged initializers.
`enum_pattern_member`, `enum_pattern_missing`, `enum_pattern_owner` and
`enum_pattern_order` enforce declared cases even in unused signatures, runtime
coverage, native owner identity and the type-only order word.
[enum_pattern_missing](enum_pattern_missing/test.md) illustrates runtime coverage
with a log viewer: labels exist for error, info and debug, but the forgotten
warning label makes compilation fail. Its explanation shows the one-line fix.

`dwarf_offsets` replaces a real binary-reader switch with composed width and
endianness methods. It uses native enums through Base.Zig, covers all four runtime
combinations and native error results, and verifies single producer evaluation,
cursor advancement, static type selection and a nested caller audit override.
Its composed `readUnsigned(reader, offsetType(format), endian)` body still works:
the need for a comptime offset type brings the format decision into that body.

`enum_demand` keeps twelve independently processed enum fields runtime until
their individual classifier calls need a case. Its guard witness requires
comptime execution, and producer counters enforce evaluation once. Named/rest
forwarding, interacting cases and pruning after known false facts exercise the
coordinate mapping. `type_selection` decodes native 32/64-bit offsets while
keeping unrelated log policies runtime through the type-producing call.
Its `open_transport` program forwards an unnamed value of
a non-exhaustive native enum without requesting enumeration; `enum_open` still
rejects case-sensitive dispatch on such a type. Tagged unions and native error
inputs retain eager refinement; genuinely interacting enums can still require
combinations.

`log_labels` checks every log level, a boolean qualifier, an explicit string
comparison, exact-case specialization, a typed default, a nested caller policy,
known-case-only coverage and input producers evaluated once. `enum_guard_order`
checks direct predicate precedence, conjunction and named argument alignment
across all four runtime levels as well as known cases.
`enum_guard_missing` preserves full runtime coverage. `enum_guard_ambiguous`
rejects overlapping qualifiers for a known case; `enum_guard_runtime_ambiguous`
rejects an ambiguous error-level branch even when the runtime fixture returns
info. Needed splits therefore retain all-arm ambiguity checks. The remaining
guard negatives enforce boolean results, lexical declarations, known inputs and
the single-fixed-input scope.

`value_guard_multi_input`, `value_guard_rest` and `value_guard_runtime` are
general guard limits, not enum behavior. The first compares account-number
values, not their int64 types. These cases record current implementation
boundaries; they do not ratify a permanently unary guard language. General
predicates on several known bound types are also still unimplemented.

`value_guard_named_type` preserves named predicate arguments; `value_guard_named_multi`
rejects a named comparison over two inputs instead of silently interpreting it
as legacy type equality. `value_guard_static` selects sensor configuration from
known integer/float thresholds. `enum_guard_member`, `error_guard_member` and
`enum_body_member` reject misspelled members in unused methods: projections from
known module values are lexical declarations, independent of execution.

`value_guard_variant` routes packet variants using their known types/tags while
leaving the payload for the chosen method. `value_guard_payload` rejects runtime
payload inspection during matching, and `value_guard_runtime_state` rejects
freezing mutable runtime policy into the dispatch table.

`error_dispatch` handles a byte or a native reader failure through ordinary
methods. It checks finite set groups and predicate qualifiers, shared native error
identity, known/error-only arms, named/rest forwarding, caller overrides, input
evaluation once, and a header validator that adds a new error to the result.
Native error-set/union joins retain compatible payloads without mixed numeric
promotion. Runtime anyerror and missing possible outcomes are rejected.

Lexical call/gate validation and export-only declarations now RUN. Typed input/
result contracts remain OPEN. `declaration_tunnel` and repaired `override` prove
source-visible requirements with caller-selected implementations;
`undeclared_call`, `undeclared_unused_call`, and `undeclared_gate` reject missing
names before instantiation. `reexport_chain`, `reexport_hidden` and
`reexport_empty_cycle` check forwarded implementations, privacy and empty cycles.

New pack promises:

- `pack_values`: empty/singleton/grouping, heterogeneous and named values, static
  projection, canonical named identity, and source-order effects.
- `pack_static`: non-type static fields survive projection, packing and calls;
  static results do not remove preceding runtime effects.
- `named_arguments`, `named_specificity`, `named_context`, `named_instances`:
  name-based binding and dominance, gates, deep caller overrides, and actual
  bound pack identity independent of permutation/runtime data.
- `named_missing`, `named_unknown`, `named_to_positional`,
  `positional_to_named`, `named_crossing`, `named_type_mismatch`: compilation
  rejects missing/extra fields, cross-fill, competing maxima and inconsistent
  explicit/inferred type witnesses.
- `named_duplicate`, `named_anonymous`, `pack_duplicate_field`, `pack_malformed`:
  frontend grammar and duplicate-label boundaries. `pack_missing_field`,
  `pack_out_of_bounds`, `pack_non_record`, `pack_empty_tail`: invalid projection
  and tuple operations fail during compilation.

Rest/splat promises:

- `varargs`: positional/named capture and construction, type values, uniform T
  versus independent predicate membership, empty witnesses, and named identity.
- `varargs_dispatch`: fixed/rest coverage, named coordinates, authored order,
  and shape tie-breaking; `varargs_empty_ambiguity` and `varargs_crossing` reject
  empty-rest and crossing maxima.
- `varargs_forward`: deep overrides, static forwarding, producer order, bound
  identity, and multiline library functions (the grammar is shared with main).
- `varargs_scale`: separate 0/1/2/8/32-element reductions; `varargs_binary_gap`
  pins the missing binary-operation diagnostic.
- `varargs_empty_unbound`, `varargs_uniform_mixed`, `varargs_type_mismatch`,
  `varargs_predicate_reject`, `varargs_sections_mismatch`, `varargs_named_type`:
  failed element constraints and type witnesses. `varargs_named_empty_ambiguity`
  checks the empty named-rest boundary. `varargs_type_pack_witness` rejects
  treating a rest of type values as one where-bound type.
- `splat_non_pack`, `splat_named_to_positional`, `splat_positional_to_named`,
  `splat_duplicate`: expansion boundaries; `varargs_not_last`,
  `varargs_two_named`, `splat_labelled`: frontend grammar boundaries.

Module promises now include `base_folder`, explicit facade/wildcard cases,
`folder_collision`, and `cycle_*` cases. Mutual imports share public dispatch
identity, private names remain file-local, and package facades control exports.
Each case's test.md specifies the exact positive or negative boundary.

The build regenerates trees and reruns negative compilation checks; cached
process results must not conceal edits to source cases or the copied machinery.

## Where machinery tests live

NOT here. `tests/` is the language suite — cases only. Machinery-level
promise tests are INLINE in `src/jpp.zig` (zig convention), including
collapse, delegation, and export gating (cross-file fixture:
`src/mixed_vis_fixture.zig`). A machinery test migrates to a case when
the surface learns to express its promise.

## Injected tables and serialization

- `enum_demand`: preserve runtime forwarding and independent case decisions,
  known-fact pruning, named/rest routing, producer effects once, precise type-result
  demand for direct arguments and generic open-enum transport.
- `enum_guard_runtime_ambiguous`: every arm of a needed runtime split must have
  an unambiguous winner under ordinary caller-first context and specificity.
- `variant_dispatch`: ordinary calls split tagged unions before selection;
  owner/tag identity, shared predicates and authored order, named/rest forwarding,
  static selected-arm coverage and type results, runtime union identity rejoining,
  and producer evaluation once.
- `variant_missing`, `variant_result`, `variant_runtime_type`, `variant_crossing`,
  `variant_owner`, `enum_open`: missing runtime coverage, incompatible results,
  escaping runtime-selected types, pointwise ambiguity, unrelated union identity,
  and rejection of requested enumeration over a non-exhaustive enum.
- [json_dispatch](json_dispatch/test.md): a modular serializer consuming the real
  std.json.Value. Four scalar variants share one method; arrays and objects share
  the container body and runtime cursor traversal. Two independent policy modules
  specialize strings/integers for Masked writers, including nested values. The
  default path is compared with std on all eight variants, escaping, raw numbers,
  empty containers and arrays of 0/1/8/128 elements. A bounded writer exposes the
  first failure and stops subsequent output/iteration. General error syntax and
  a full JSON library are outside this case.

Inline machinery tests also exercise plain enum value patterns, static/runtime
selection, named multi-enum tables, rest capture, delegation with separate selection
and execution contexts, and enum-value signature inclusion/intersection. Static
union payloads retain slice values; variant metadata cannot forge native identity.
