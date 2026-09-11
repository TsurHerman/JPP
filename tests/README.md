# tests/ — the language's promises, as executable claims

Each folder is a CASE: a complete jpp tree whose PROGRAMS validate
one language aspect. A program is a root module that defines `main`
(filename is free). Assertions run in the language: `using Test` and
`check(name, got, want)` printing `ok <name>` / `FAIL <name>: got X
want Y`. Check names name the ASPECT, never the probe data.

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

Cases: `dispatch` (selection + the specificity ladder, as values),
`caller_context` (caller-provided arithmetic; lexical dependency checking
remains a gap), `override` (position shadowing through a library),
`depth_override` (surgical override through two
modules), `context_flip` (opposite orders, flipped winner),
`folder_modules` (aggregate, takeover, dotted addressing),
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
checks the same import rule for equality gates; `undefined_export` prevents
an export list from inventing a definition.

`Any` is an ordinary imported predicate. `any` checks direct calls, retained
types, predicate rank, and the authored Base order. `any_override` and
`any_shadow` check caller overrides and source-tree replacement;
`any_order_gap` and `any_unimported` reject hidden order and builtin names.

[checkout](checkout/test.md) is an application case study: nineteen source
modules, thirteen baskets in two contexts, and 105 assertions covering
discounts, rounding, delivery, tax, records, and accounting identities.
It records the ergonomics of shared arithmetic, explicit domain imports,
deep policy overrides, and the missing local-binding/record/variadic surface.

## Promise catalog and coverage

| # | Promise (README ref) | Covered today | Boundary tests to write |
|---|---|---|---|
| 1 | Specificity ladder: exact type value > exact input type > pred > bare; dominance, never sum (§4, §9) | `type_values` (type value versus input type); `dispatch` (exact/predicate); `where_gate` (long and short predicate spellings, authored Any fallback); `any` (predicate above bare); `pointwise_gap`, `gate_conjunction`; machinery tests (bar lattice, full ladder) | per-slot projections with variadics |
| 2 | Ambiguity: same-module crossing = comptime error at the call; intersection cures (§9) | `ambiguity`, `where_gate_clash`, `pointwise_gap`, `order_cycle` (negative cases); machinery tests | — |
| 3 | Ordered context: position breaks ties; flip flips (§1, §9) | `override`, `context_flip`; machinery tests | — |
| 4 | Context accumulation: caller ahead, callee STATIC behind (§1) | `depth_override`, `caller_context`, `equality_scope` | direct extendAll-ordering test |
| 5 | Depth overrides: surgical, unlimited (§1, §10.5) | `depth_override`, `collapse_imports`; `checkout` (4+ levels, discount and freight overrides at different depths) | recursive call graphs |
| 6 | Delegation `M.f` (§1) | machinery tests | surface `M.f` (parser) then a case |
| 7 | Collapse: resolving module owns the instance (§9) | `collapse_dependencies`, `collapse_imports`, `checkout`; machinery tests | symbol-hash stability once hashes land |
| 8 | Exports gate everything (§1) | `export_gate`, `private_downstream` (negative); `private_helpers`; machinery tests (fixture) | `M.f` qualification path once surface lands |
| 9 | The `<:` order word (§9) | `order_injection`, `order_refines`, `order_variables`, `order_negative`, `type_bindings`, `lattice` (diamond), `lattice_bridge` (caller closes a gap); machinery tests (7 ironing cases) | transitive closure: `lattice_gap` pins that there is none, and that the gap is an ambiguity |
| 16 | Operators are ordinary words: infix is surface only (§4) | `pred_join` (`\|\|`, `&&` defined over bool, exported, precedence pinned); `checkout` (shared `+ - * /` provider inside the example); machinery tests (`+` shadowed) | standard Base arithmetic library |
| 10 | Binder: packs, named args (§4) | binderprobe (spike) | surface named args |
| 11 | Enum bridge (§4) | enumprobe (spike) | surface selectors |
| 12 | Parametric type-words (§4) | vecprobe (spike) | surface braces |
| 13 | Folders are modules: aggregate, takeover, dotted (§1) | `folder_modules`, `folder_scope`, `private_helpers` | nested aggregates (folder of folders) |
| 14 | Tier invariance (§9) | — | needs tier infrastructure |
| 15 | Library resolution: modules from `Base/`, tree shadows Base | all check-based cases (implicitly); `any_shadow` explicitly replaces a Base module | — |
| 17 | Defined signature names require lexical definitions/imports | `declaration_names`, `undeclared_order`, `undefined_export` | user-defined type/constant declarations after that surface exists |
| 18 | Annotated inputs may be unused; anonymous universal predicate inputs use `<:Any` | `unused_ground`, `any` (positive); `unused_input`, `unused_untyped_ground`, `unused_anonymous` (negative) | richer pattern syntax |
| 19 | Type values and bound return types survive calls | `type_values`, `type_bindings`; machinery pack test | general static value selectors |
| 20 | Every where variable must bind somewhere | `unbound_where` | arbitrary where expressions |
| 21 | Ground inference preserves runtime data and intentional static fields (§7) | `ground_records`; `checkout` (native record pipeline and void statement emission) | richer record surface |

Call dependency contracts remain OPEN: the existing caller-context cases
prove selection and propagation, but not lexical call validity. The
[research proposal](../design/word_contracts.md) separates those tests from
the additional contract tests needed before the boundary can be claimed.

## Where machinery tests live

NOT here. `tests/` is the language suite — cases only. Machinery-level
promise tests are INLINE in `src/jpp.zig` (zig convention), including
collapse, delegation, and export gating (cross-file fixture:
`src/mixed_vis_fixture.zig`). A machinery test migrates to a case when
the surface learns to express its promise.
