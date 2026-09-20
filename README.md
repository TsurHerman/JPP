# jpp — language definition (working draft)

Julia-class scientific computing, taken seriously about compilation.
Dynamic feel while developing; everything is native code all the time;
sealed builds are small static binaries. Reference document:
[Julep: Taking multiple dispatch, export, import, binary compilation seriously](https://discourse.julialang.org/t/julep-taking-multiple-dispatch-export-import-binary-compilation-seriously/10882) (2018).

Guiding principle — **julia-9/10**: when a question is about numerics or
surface culture, Julia's answer is jpp's answer. Deviations are explicit
and registered (see bottom).

**To run anything** (demo, tests, probes): see `RUNNING.md` — one
dependency (zig 0.16), five `zig build` steps. The language-promise
test catalog lives in `tests/README.md`.

Syntax coloring for VS Code/Cursor and local HTML rendering is available in
[`editors/vscode/`](editors/vscode/README.md), using one shared TextMate grammar
with embedded Zig highlighting. This is editor tooling; semantic IDE features
such as diagnostics and go-to-definition remain unbuilt.

## How to read this document

This is a DESIGN LEDGER first: it records every ratified decision with
its rationale, in the order the design was argued. It therefore mixes
tenses. Four kinds of truth appear, and **unless a passage says
otherwise, assume RATIFIED — decided, not built**:

- **RUNS** — in the v1 pipeline today (`zig build demo`); §10.5 is the
  authoritative list of what that includes and its scope cuts.
- **VALIDATED** — implemented and tested in the machinery
  (`src/jpp.zig`) or proven in a probe (`spike/`), but with no surface
  syntax yet: the transpiler can't parse it, the semantics engine
  already speaks it.
- **RATIFIED** — decided design, recorded here, unbuilt. The
  `design/` notebook distinguishes future work from runnable tests.
- **OPEN** — research (§11).

Status of the major features:

| feature | status |
|---|---|
| dispatch core: exact/bare quals, dominance, position, context accumulation, depth overrides | RUNS |
| conservative context collapse across deeper imports; lexical private helpers and exported fusion | RUNS (collapse_dependencies, collapse_imports, checkout, private_helpers, private_downstream) |
| ground `zig{}` bodies, inferred returns across the boundary, runtime records with static fields | RUNS (ground_records, checkout) |
| predicate gates `where T <: Integer` (sugar for `Integer(T)`); predicates are ordinary words qualed on `::type` | RUNS (where_gate) |
| predicates DEFINED from predicates (joins/meets), so `where` needs no boolean combinators | RUNS (pred_join) |
| infix operators are ordinary overridable words: `\|\| && == + - * /`, precedence loosest-first | RUNS (pred_join pins boolean precedence; value_equality covers equality) |
| explicit Base namespace/facade, recursive folder imports, wildcard siblings, and public import-cycle units | RUNS (base_folder, folder_modules, cycle_imports, cycle_folder; facade and privacy negatives) |
| immutable local bindings name ANF values without repeating calls | RUNS (local_bindings, checkout; binding_* frontend rejection cases) |
| immutable module constants, native namespace access, and lexical enum case patterns | RUNS (static_bindings, dwarf_offsets; static_binding_* and enum_pattern_* rejection cases) |
| value predicates and classifier comparisons in `where`, evaluated from known branch facts | RUNS (log_labels, enum_guard_order, value_guard_variant; guard rejection cases) |
| native error sets and error unions use the same injected dispatch mechanism | RUNS (error_dispatch; error coverage, open-set and result rejection cases) |
| predicate quals in SLOT position: `x<:Integer` ≡ `x::T where Integer(T)`, same rung | RUNS (where_gate, order_refines) |
| ambiguity-at-the-call error, export gating | RUNS (negative cases: compile must fail) |
| declarations distinguish defined values, annotated inputs, fresh binders, and anonymous inputs | RUNS (declaration_names, unused_ground; negative: undeclared_order, unused_input, unused_untyped_ground, unused_anonymous) |
| `Any` is an ordinary imported predicate with authored fallback order | RUNS (any, any_override, any_shadow; negative: any_order_gap, any_unimported) |
| exact type values, type-domain inputs, type-returning calls, and bound return types | RUNS (type_values, type_bindings) |
| the type-only `<:` word: defined class/type facts, negative facts, general rules | RUNS (order_refines, order_variables, order_negative; negative: order_type_only, order_bool) |
| `<:` is consulted PAIRWISE between candidates — no transitive closure; a chain conducts only through classes carrying a method, and the caller can supply a missing link | RUNS (lattice, lattice_bridge; negative: lattice_gap) |
| direct mutual `<:` pairs; no implicit equivalence closure; cyclic strict order diagnosed | RUNS (type_bindings; negative: order_cycle); legacy gated edges VALIDATED in machinery |
| delegation `M.f` (select in M, propagate caller) | VALIDATED (machinery) — no surface |
| specificity policy as shadowable word; stratum-0 self-reference break | VALIDATED (probe + machinery) |
| demand-driven enum tables and automatic tagged-union tables in ordinary calls | RUNS (enum_demand, variant_dispatch, json_dispatch, dwarf_offsets and rejection cases), including source enum case patterns |
| enum interface as a tight Zig wrapper authored in jpp | native types/cases accessible through Base.Zig; generic staged branch/library protocol remains OPEN |
| general selectors `{}` and integer range arms | VALIDATED (probes); surface syntax remains unbuilt |
| tuples/records, static projections, two-section named calls, name-aligned dispatch and bound-instance convergence | RUNS (pack_values, pack_static, named_arguments, named_specificity, named_instances, named_context) |
| positional/named rest capture, splats, elementwise predicates, uniform rest types, and shrinking reductions | RUNS (varargs, varargs_dispatch, varargs_forward, varargs_scale, checkout; rejection cases) |
| parametric type-words, pattern binding, re-application provenance | VALIDATED (probe) |
| comptime `for` generating methods (staged codegen), promotion/convert corpus, braces in surface | RATIFIED — design notebook; surface unbuilt |
| repeated type binder = identity; `where T == S` = mutual direct relation; all predicate conjuncts participate in dominance | RUNS (type_bindings, where_gate, gate_conjunction; negative: pointwise_gap) |
| tiering & hot-swap, symbol-name-as-cache-key, sessions | RATIFIED (soprobe touches the dlsym venue) |
| memory model, threading, stdlib strategy, tensors, macros, ledger tooling | OPEN (§11) |
| export-only word declarations, imported re-exports, and lexical call/gate checks | RUNS (declaration_tunnel, reexport_chain, override; undeclared and missing-implementation negatives); typed contracts remain OPEN |

---

## 1. Dispatch semantics (the founding idea)

- **No global method table.** A call resolves against the caller's
  *context*: the methods lexically visible at the call site (its module
  plus imports).
- **Fusion on `using`.** Importing two modules that define the same
  function name fuses their method sets in your context. Collisions are
  only errors on actual signature overlap within one module; across
  modules, order decides (below).
- **Delegation on qualification (ratified, validated:
  `spike/interpprobe.zig`).** `M.f(x)` resolves the WORD `f` in M's
  own context `[M, M's usings...]` — selection — but the chosen method
  executes with the NORMAL accumulated context (caller's chain ahead,
  `++` home STATIC): the body's ANF ops stay caller-derived.
  Delegation overrides WHO ANSWERS, not what words mean inside — one
  propagation regime, no hermetic islands, the founding thesis is
  never switched off for a subtree. (Validated: a caller shadowing
  both `double` and `+` gets its own `double` unqualified; delegating
  `lib.double` selects lib's method while `+` inside still resolves to
  the caller's override.) Guarantees that matter are hermetic anyway:
  `ints.+` on concrete ints selects a GROUND method — an axiom with no
  dispatch inside; hermeticity is a property of bottoming out in
  ground, not of qualification. Machinery: the call primitive has a
  two-context form — resolve with M's tuple, execute with the
  caller's. The entitlement dial: `using` takes standing to shadow the
  selection; `M.f` waives selection at one call site (meaning inside
  still flows down).
- **Folders expose packages (RUNS).** A file `folder/worker.jpp` is
  `folder.worker`. `using folder` uses `folder/folder.jpp` as its facade when
  present, exposing that file's exports. Otherwise it aggregates the folder.
  `using folder.*` explicitly collects the other files and subfolder interfaces,
  excluding the facade itself. Subfolder facades control their own interfaces.
  Individual files remain addressable; `folder.folder` names the facade explicitly.
  Same-source `folder.jpp` plus `folder/` is an ambiguous path and is rejected.
  A root file defining `main` is a program; each program starts a fresh context.
- **Base is an explicit namespace (RUNS).** Write `using Base` to import the
  public interface selected by `Base/Base.jpp`. It uses `Base.*` and re-exports
  arithmetic, boolean words, equality, isOneOf, Any and its authored order,
  Tuple utilities, and check. Narrow
  imports such as `using Base.Arithmetic` or `using Base.Test` are also available.
  No import is inserted automatically. A file must declare its own dependencies;
  a program's imports do not repair a library's undeclared calls.
  A source `Base/Any.jpp` replaces that bundled leaf. A source-root `Base.jpp`
  replaces the bundled root interface; this is cross-root shadowing, not a
  same-source file/folder collision. `Base.Arithmetic` supplies `+`, `-`, `*`,
  `/`, and `div`; Base no longer ambiguously names an arithmetic leaf.
  Int64 +, - and * wrap; float64 arithmetic is ordinary floating arithmetic.
  `/` returns float64 for either same-type pair; int64 div truncates toward zero.
  Mixed promotion and other widths remain unbuilt. All imports retain ordinary
  caller-first context priority; put an intended caller override ahead of Base.
- **Mutual imports form one unit (RUNS).** Import cycles, including longer
  cycles through folders, share one public dispatch position. Importing an ordinary
  member exposes the unit's public words; a facade still restricts its package
  interface to authored exports, even when it participates in a cycle. Competing maxima in that unit are
  ambiguous at the call, independently of entry member. Private visibility
  remains file-local, and original method homes survive composition. This is
  module-graph connectivity, unrelated to the pairwise `<:` relation.
- **Exports gate everything (ratified).** A word callable from outside
  its module — by fusion (`using`) OR by qualification (`M.f`) — must
  be labeled `export`. One closed interface per module; internals
  exist only inside the declaring module. RUNS: exported names participate
  in caller-context fusion. A private declaration and its local references
  lower to a module-specific internal key that cannot be spelled in jpp
  source. This permits private helpers to run without allowing caller
  shadowing or downstream capture. Folder aggregation preserves each
  method's declaration home for body execution and predicate applicability
  (`private_helpers`, `private_downstream`, `folder_scope`). Imports do not
  automatically re-export their dependencies. An exported word with no local
  methods forwards public imported implementations; when none exist it is a
  declaration-only dependency. It never becomes a dummy candidate. Authored
  local methods remain that file's own contribution. Re-export traversal reads
  raw authored sets, preserves homes, and handles cyclic declarations finitely.
  A facade can therefore select its package API without wrapper functions.
- **Ordered context (ratified, supersedes the hard extension-only
  rule).** A context is an ordered list `[caller's chain..., imports in
  order...]`. Resolution: specificity first; on rank ties, earlier
  position wins. Same-territory re-coverage is legal *shadowing* —
  newer code can override old behavior deterministically. Piracy stays
  impossible for the original reason: an override only affects
  resolutions in contexts that include it. Competing maxima in the winning module
  are an error at the call, during Zig comptime instantiation.
- **Context reaches downward, and accumulates.** Entering a resolved
  method, the effective context becomes `caller_ctx ++ callee's static
  context` (deduped, caller stays ahead) — so the caller's overrides
  outrank even the callee's own imports. Generic code (`sum` calling
  `+`) sees the caller's extensions. Context is a compile-time
  specialization parameter, monomorphized away — never a runtime value.
  **Lexical dependency checking (RUNS):** called words and gate words must be
  defined, explicitly imported, or declared by export in their source scope.
  This checks unused bodies too. Emitted REQUIREMENTS data records those names;
  a caller can select implementations but cannot introduce missing declarations.
  Export-only words do not prove universal coverage. Stronger argument/result
  contracts remain OPEN in [word contracts](design/word_contracts.md).
- **Compiled instances are keyed by `(function, argument types, context
  methods actually reached)`.** All keys static. Editing a module
  invalidates exactly the instances that reached it — invalidation flows
  toward callers, never into the base libraries. (The invalidation model
  is the push/pull signal graph of Signals.jl, applied to compilation.)

## 2. Types, values, comptime

- Types are ordinary compile-time values. Functions on types are
  ordinary functions that run at compile time.
- **Module constants (RUNS, 2026-09-20).** `Name = value` binds an immutable
  comptime value in its declaring module. Initializers currently admit scalar
  literals, defined names, member paths and explicit `zig{}` grounds. Module
  dependencies may point forward; value cycles error. Ordinary calls in module
  initializers await a general staging/context contract and are rejected today.
  Constants are private unless exported; facades, re-exports and public import
  cycles preserve their identity. Local declarations precede imports; imports
  are searched in source order. An aggregate can coalesce identical values but
  rejects different values or a value/method collision under one public name.
  A module cannot redefine a builtin type or give one name both a value binding
  and methods. Binding a callable value does not implement callable application.
- **Native namespaces (RUNS).** `using Base.Zig` imports an ordinary library
  constant, Zig. `Format = Zig.std.dwarf.Format` retains the actual native type;
  `Format.32` retains its actual case value. Static member access also reads
  native namespaces and public constant declarations on types. It creates no
  new enum owner or runtime wrapper. Native function invocation still uses
  explicit grounds. Base's default facade does not re-export Zig.
- Top level runs at compile time; there is no "load time".
- `for` at top level runs at comptime and can *generate methods* —
  this is jpp's `eval`: staged codegen, closed by the build. (RATIFIED
  — design surface only; the v1 parser has no `for`. The demo's ground
  families are written out by hand; the design notebook discusses staged generation.)
- Functions are comptime values (`for op in (+, -, *) { ... }` — same
  status: ratified, not yet parseable).
- Integer literals are comptime ints (arbitrary precision, adapt to the
  consuming site, Zig-style). `x + 1` never causes promotion.
- **There is no runtime `eval`.** "Dynamic" means the compiler is in the
  room: in a session, an unknown-type dispatch is a cache miss (compile,
  patch the slot, proceed). Sealed builds close the world; a program
  needing runtime openness opts into `--embed-compiler`.

## 3. Predicates replace the abstract type tree

There is no `Integer <: Real <: Number` tree. In its place: predicates —
comptime functions `type -> bool`. Default answer `false`; specific
methods answer `true`; most specific wins.

```
Integer(T::type) = false
Integer(int32)   = true          # one method per machine type
Unsigned(T::type) = Integer(T) && !Signed(T)
Real(T::type) = Integer(T) || Float(T)
```

**Naming convention (ratified):** Capitalized = predicates, the
annotation vocabulary (`x<:Integer`, `T::Signed` — adjectives).
lowercase = value-returning functions (`bits(T)`, `signed(T)` — verbs).
`Signed(T)` asks "is it?"; `signed(T)` answers "give me the twin".

**Predicates are words; the matcher is ground (ratified).** Predicates
are ordinary multimethods — extensible, context-resolved: a module CAN
teach `Integer` about `int128`, and applicability itself becomes
caller-derived (extending `Integer` in your context makes `ints.+`
match the new type downstream — the founding sentence, again). The
circularity this creates (matching needs predicate meaning, predicate
meaning needs dispatch, dispatch needs matching) is broken by making
the MATCHER the axiom: ONE non-overridable Zig comptime function in
the runtime library evaluates pack-against-pattern in context. It is
machinery, not a word — never dispatched, never overridable. Predicate
cycles (P's signature mentions Q, Q's mentions P) are data the ground
matcher handles Signals.jl-style: an explicit in-progress set threaded
through as a parameter (comptime has no mutable globals); in-progress
resolution answers "no match". Known cost: every resolve may trigger
predicate resolves — the ground matcher is where the comptime-cycle
risk (§11) concentrates, so it is also where mitigation lives.

## 4. Annotation grammar (ratified)

**The complete shape of a method definition:**

```
F{a::int32, B<:Integer, mode}(c::T1, d<:Real, rest...; eps::float64)::R where P(B, T1) = body
  └─ selectors ─────────────┘└─ tuple ──────────────┘  └─ record ──┘ └ret┘ └─ last gate ─┘
```

- **Braces — selectors**: what the specialization is chosen BY. `F{...}`
  returns a comptime value, commonly a type; every type has its `()`. General
  value/range selector syntax remains unbuilt. Automatic enum and tagged-union
  tables also apply to ordinary paren calls (RUNS, revised 2026-09-15); they no
  longer require a selector section. The proposed bool and bounded-integer
  bridges remain separate work. Open domains (types, comptime_int, floats,
  strings) remain comptime-only selectors.
- **Parens — the call pack**: runtime data dispatches on its type. Type
  values also travel through this pack, with their identity preserved in
  comptime fields. Thus `f(int64)` can select a different method from
  `f(float64)` without treating integer data as static selectors. Direct enum
  and tagged-union inputs now receive an injected table before method selection;
  other runtime data continue to dispatch on type.
  Positional tuple, then `;`, then named record (required named inputs RUN).
  No cross-fill; declared order is canonical.
- **Return** optional; absent = inferred (body mirrored in context).
- **`where` — the last gate**: ONE comptime predicate over everything
  the signature bound (selectors, implicit type vars, named-slot
  types). Runs last in the binder; failure is a quiet no-match. Sugar
  identity: `B<:Integer` ≡ `B` + `where Integer(B)`, same rank.
  Two type-var forms are **not** sugar for each other:
  `f(a::T, b::T) where T` — one binder, repeated: `typeof(a)` **is**
  `typeof(b)` (the same type). `f(a::T, b::S) where T == S` — two
  binders plus `=={T,S}`, defined as the two direct queries
  `T <: S && S <: T`. This relation does not imply a transitive quotient. Mutual edges `mynum <: Integer` and
  `Integer <: mynum` let those types **mix** in the second form; the
  first still rejects them as different types. **Layering (ratified,
  not circular):** reflexivity of `<:` (`P <: P`) is an unshadowable
  machinery axiom — the two arguments are the same predicate, Zig
  identity of the type values (or fn values in the legacy edge probes). jpp `==` is *derived from*
  `<:`; never the reverse. `<:(P, Q) where P == Q = true` is
  forbidden: `==` would consult `<:` which would consult `==`.
  Infix `T == S` in `where` is `=={T,S}`. Not Zig `==`, not Julia's
  `T==S` (Julia is identity; jpp identity of types is repeating the
  binder).
- **Body**: expression block (value = last expression) or ground axiom
  (`zig{}`, `c{}`, `llvm{}` — no context dispatch inside). Every function
  can use a multiline `{ ... }` body; main has no special body grammar.
  Parameter lists and calls can span lines too. Short compositions can remain
  single expressions (`varargs_forward` exercises a multiline library function).
- **Specificity per supplied slot**: fixed coverage precedes rest coverage;
  within either, exact type value 4, exact input type 3, predicate 2, bare 1.
  If all supplied coordinates tie, a strictly narrower structural pack shape
  can decide (including fixed empty shape versus rest);
  pointwise dominance decides (§9 policy word); incomparable-or-equal
  maxima break by context position across modules, and are a comptime
  ambiguity error AT THE CALL when they share the winning module
  (julia's venue — define the intersection method).
- **Underneath**: the signature is a pack CONSTRUCTOR; calling is
  constructing the parameter struct (the binder); the bound pack is
  the instance identity and the `.so` symbol key.

**Declaration names and types as values (RUNS; revised rule).** A name
already defined in the declaring module, explicitly imported from an export,
or supplied as a builtin type denotes that existing value in a signature.
A fresh name introduces an input variable, regardless of capitalization.
An export declares the word's identity and forwards public imported methods
when available. Otherwise it is a declaration-only dependency with no invented
implementation (`undefined_export`, `declaration_tunnel`, `reexport_chain`).
A caller's later context does not create lexical definitions. The lookup
is performed by the comptime machinery using emitted declaration metadata;
the transpiler stays file-local and never computes an effective context.

```jpp
using preds                 # preds defines and exports Signed and Wide
export <:
<:(Signed, Wide) = true      # one pair of existing class values
<:(::type, ::type) = false   # intentional general rule, no ignored names
```

Removing `using preds` makes `Signed` and `Wide` fresh variables. Because
the body uses neither, this is an **unused-input error**, not an order fact.
This check applies to unused, **unannotated** fresh names in every word,
including methods not called. An explicit type or predicate annotation
already gives an input a role in the signature; the body need not read its
value. `f(x::int64) = 42` is a valid constant function on integers, whether
its body is ordinary jpp or a ground. Repeated type variables and predicate
gates also retain their constraints when the values are unused.

Anonymous inputs remain an option: `<:Any` for an input accepted by the
ordinary Any predicate, `::int64` for an
integer, `::type` for a type value, and `<:Signed` for an input gated by
Signed. A name used in a return annotation or a constraint is meaningful
too. Thus `<:(P::type, Q::type) = false` is an explicit general rule, while
the unannotated, undefined `Signed`/`Wide` example above still errors.
Bare `_` is also an unused unannotated input and errors. `x<:Any` may keep
a name without using it. Like all predicate inputs, both spellings retain
each concrete input's type and value, with no boxing or erased runtime
representation.

**Any is library code, not a builtin type or compiler wildcard (RUNS).**
`using Base.Any` (or the Base facade) imports `Base/Any.jpp`, which defines:

```jpp
export Any, <:
Any(::type)::bool = true
<:(::type, Any) = true
```

`Any(int64)` is an ordinary predicate call. `<:Any` has predicate rank 2,
above an unconstrained binder and below an exact input type. Its fallback
priority relative to other predicates comes from the authored order method
above, when that module is in the comparison context. Merely defining an
always-true predicate does not create an order edge (`any_order_gap`).
Caller overrides can change membership; a source-tree `Any.jpp` can replace
the Base module, including its order. The name requires a definition/import.
`Any` as a value denotes its ordinary word/class identity. `::` still
specifies an exact input type; predicate inputs use `<:`. Results follow
normal inference or a concrete/bound return annotation, with no Any-specific
return rule.

A predicate word remains callable (`Signed(int64)` tests membership) and
has a type-level class identity when passed as a value. Exported
contributions share the identity of their word; private identities remain
local. The implementation's `Word` representation does not introduce
undefined source names. An order fact is an authored relation; it neither
proves set inclusion nor adds members to the predicate's definition.

| declaration | accepted argument |
|---|---|
| `f(X) = X` | any input, bound to fresh `X` |
| `f(<:Any) = 0` or `f(x<:Any) = 0` | any input under Base's imported predicate, allowed to be unused |
| `f(::int64) = 1` | an integer value |
| `f(::type) = 2` | any type value |
| `f(int64) = 3` | the specific type value `int64` |
| `f(Signed) = 4` | the existing class value `Signed` (definition/import required) |
| `typeof(::T) where T = T` | any input; returns its inferred type |

Type values survive binding, forwarding, ANF results, and ground calls as
comptime fields. Type-returning methods must compute their result from
information available at comptime; runtime values are not automatically
promoted to static selectors. `f(x::T)::T where T` expresses a bound return
type in either an ordinary body or a ground. The full brace/constructor
surface below remains future work.

**Parametric types are brace-only words returning types.**
`Vector{T<:Real, N::int} = zig{ struct { data: [N]T } }` — this is
Zig's own generics model (comptime fn returning a struct type,
memoized: same selectors, same type) wearing julia's surface
(`Array{Float32,2}` = type application). No new primitive. Three uses:
construction `Vector{float32,2}(xs)` (the returned type's `()`); exact
annotation `x::Vector{float32,2}` (`::` takes a type; the brace
expression evaluates to one, rank 3); pattern annotation
`x::Vector{T,2}` with free binders (rank 2 — a pattern is a
predicate). The pattern form desugars like `<:` does: first occurrence
of a free binder BINDS (`T := elem{A}`), repetition CONSTRAINS
(`elem{B} == T` — unification-lite, all comptime), user's `where`
gates last. Matching runs type application backwards, so type-words
STAMP their selectors into the returned type as decls (auto-stamped by
the future struct sugar), and provenance is checked by
RE-APPLICATION, not stamp trust: `made_by{A, Vector}` =
`A == Vector{A.Elem, A.len}`. The probe's generative struct constructor
returns a distinct identity per selector pack, so forged stamps cannot
pass that check. Memoization alone does not make an arbitrary type-returning
function injective. Validated for this constructor:
`spike/vecprobe.zig` (bind, unify, where-gate, impostor rejection). A
`struct`-style sugar for field syntax (avoiding hand-written `zig{}`)
is wanted eventually, julia-9/10.

**Two planes, one verb (the capstone).** `{}` computes in the comptime
plane and returns a comptime value — paradigmatically a TYPE, which is
frozen code: a thing that accepts arguments and returns something.
`()` computes in the value plane. Every type is callable and calling
it is construction (`int8(14)`, `Vector{f64,2}(data)`,
`convert{f64}(x)`); every method call is the construction of its
parameter struct — method application and type construction are ONE
operation read in both directions. Dispatch, specialization, and
meaning are settled entirely in the brace plane; parens move values
through code whose meaning is already frozen. The comptime-ness is
semantic, not syntactic: a runtime closed-domain selector is ferried
across by the bridge (one arm per variant), never actually runtime
inside. Definition vs application is the same operator in two
positions: `F{T<:Real, N::int} = ...` declares the family, `F{f64,2}`
selects the member.

Parked: defaults on named slots; bare `F{a}` with a runtime selector
(must be immediately applied — a runtime-selected type may not leak);
`struct` declaration
sugar for parametric type-words.

Argument position:

| form         | meaning                                            |
|--------------|----------------------------------------------------|
| `x::int32`   | exact type. `::` annotates what the argument IS — no puns |
| `T::type`    | the argument is a type value (kind annotation)     |
| `x<:Integer` | guard on the TYPE of x — `Integer(typeof(x))`      |
| `::type`     | anonymous input whose value is a type             |
| `int64`      | the particular, already-defined type value         |
| `where P(A)` | predicates on comptime values go in `where`        |
| `x::T` … `where T` | bind `T := typeof(x)`; repeating `T` is identity |
| `where T == S` | infix for `=={T,S} = T<:S && S<:T` (not identity) |

Brace position — extra comptime parameters, **only** those not inferable
from the value arguments; supplied at call site as `f{T}(x)`:

| form               | meaning                                       |
|--------------------|-----------------------------------------------|
| `f{T}(x)`          | bind any comptime value (generic)             |
| `f{T<:Integer}(x)` | bind + predicate; sugar for `f{T}(x) where Integer(T)` |
| `f{Integer}(x)`    | anonymous predicate slot (name unneeded)      |
| `f{int32}(x)`      | EXACT comptime value — most specific          |

**Tuple and named values (RUNS).** `()` is empty, `(x,)` is a singleton,
`(x)` remains grouping, and tuples can mix element types without promotion.
`(; tax = x, freight = y)` constructs a structural named value; `(x; label = y)`
constructs both sections. Named identity uses field names/types/static values,
independent of spelling order. Named value storage sorts names; selected bound
packs use method declaration order. Neither specifies a foreign ABI. `.0` and
`.name` project static fields. Base.Tuple supplies len, first and tail. Producers
run once in source order; canonicalization only routes their completed results.

**Static fields (RUNS).** Explicit comptime fields, including native integer
selectors, retain their actual values through packing, projection, and identity
forwarding. Runtime data and ordinary source literals contribute only their types
to specialization. A static result does not erase a call's preceding runtime
effects. General static arithmetic, brace syntax, and callable aliases are later
work. See [packs](design/packs.md) for the field and dispatch decision tables.

Variadic and tuples (RUNS):

- `f(xs...)` captures remaining positional inputs as one tuple;
  `f(; opts...)` captures remaining named inputs as one named record. One rest
  is allowed per section and must be last in that section.
- `f(xs...; opts...)` forwards both sections. Splats also work in pack values:
  `(head, xs...)` and `(; required = value, opts...)`. A splat operand evaluates
  once before routing; its shape must be known statically. A positional splat
  accepts only positional fields, a named splat only named fields. There is no
  cross-fill or last-wins overwrite; duplicate expanded names are errors.
- `xs::T... where T` binds one shared element type; `xs<:Numeric...` instead
  checks Numeric for each element and permits heterogeneous types. An empty
  uniform rest needs another T witness. An empty independently typed/predicate
  rest is vacuous; two overlapping empty rests gain no preference from their
  element constraints.
- `len(xs)`, `first(xs)`, and `tail(xs)` take a tuple as one argument. `()`
  splats to zero arguments; tail of a singleton is `()`. Brace syntax remains
  unbuilt and will use the same pack semantics.
- Reductions need explicit zero/one/binary domains, followed by a shrinking
  three-or-more case. A missing binary operation must diagnose that operation,
  not recurse into the same variadic fallback (`varargs_binary_gap`).
- Compare actual supplied coordinates pointwise, with fixed coverage before
  rest coverage. Rest element constraints use the ordinary ladder and authored
  pairwise order. Shape only breaks ties; it cannot cure a crossing coordinate.

- **Methods are unary (ratified).** A method takes ONE argument: a
  struct (the pack). `f(a, b)` constructs the anonymous pack `(a, b)`
  and applies f to it; the parameter list is a PATTERN over the pack's
  fields; dispatch is structural dispatch on the pack's single type
  (instance key: method × context × pack type). A variadic method
  can constrain its rest elements; destructuring uses ordinary tuple/record
  operations (`len`, `first`, `tail`, field access).
  Splat is a cast, not a computation: `f(t)` wraps t as a one-field
  pack, `f(t...)` uses t AS the pack. Consequences: named fields are
  keyword arguments that PARTICIPATE IN DISPATCH (julia's kwargs
  don't); uniform `fn(ctx, pack)` signatures ease musttail. Named constraints compare by field name, independent of declaration order (RUNS). This ratifies what the
  emission already did — `jpp.call(ctx, "f", .{a, b})` was always
  unary.
- **The pack is two sections; the binder is the semantic layer
  (RUNS; also validated by `spike/binderprobe.zig`).** A pack is an
  ordered TUPLE (positional) followed by a RECORD (named). The
  convention holds at call sites and in definitions: positional slots
  are a prefix, `;` opens the named section (julia's kwarg separator —
  julia-9/10). Binding never crosses sections — positional slots fill
  by index only, named slots by name only — so the dispatch footgun
  (methods differing only in slot order colliding through named calls)
  is grammatically impossible. Named args permute freely among
  THEMSELVES (a record is a set); the method's declared order is the
  canonical form. The call-site protocol: (1) the transpiler emits the
  operand sequence exactly as written; the machinery expands splats into the
  RAW pack — positionals as numeric field names
  `.@"0"`, `.@"1"`, named verbatim (the frontend rejects duplicate explicit
  names; expansion rejects duplicates introduced by splats); (2) each candidate method's
  BINDER attempts to construct its parameter struct from the raw pack —
  calling a method IS constructing its parameter struct, the signature
  IS the pack constructor; failure (unknown name, cross-fill, arity) is
  a quiet no-match, another method may arrange differently; `where`
  validates last; (3) resolution picks the best successful binder
  (rank, then context position); (4) the BOUND pack type — declared
  slot order, never the written order — is the instance identity:
  method × context × bound pack × tier. Zig's comptime memoization is
  the instance table (permuted spellings converge to pointer-identical
  instances — validated), and the `.so` symbol hash is computed over
  the bound form, so permuted call sites hit ONE symbol. Interface
  consequence: `matches: bool` dies — it cannot say which raw field
  feeds which slot; its replacement is `bind(ctx, RawPack) ?BoundPack`.
  Defaults for named slots: not yet ratified, parked.
- **One pack — comptime fields included (ratified).** The comptime
  pack and the runtime pack are ONE struct. Zig already agrees: tuple
  fields of comptime-only type (`type`, `comptime_int`) become comptime
  FIELDS, their values baked into the tuple's type. So the pack type
  alone carries the runtime fields' types AND the comptime fields'
  values, and the matching rule collapses to one sentence: **matching
  is a predicate on the pack type.** For a runtime field the pattern
  constrains its type; for a comptime field, its value — both are facts
  of the pack type. Same specificity ladder. `f{A}(b)` lowers to the
  pack `(A, b)`, indistinguishable from `f(A, b)` — and that is
  julia-9/10: jpp's `convert{T}(x)` IS julia's `convert(Int, x)`.
  Braces are surface emphasis and slot-placement sugar (leading
  fields), not a calling convention. Consequences: **promote is ONE
  word** — the `@"promote{}"` decl key dies, one MultiMethod binds the
  all-comptime senses and the value senses alike; `Tensor{f64,2}` is
  just a word whose pack is all-comptime and whose return is a type.
  One-way door, welded deliberately: brace application can never mean
  something paren application can't.
- **Injected dispatch tables (RUNS; revised 2026-09-20).** The source is a
  collection of ordinary method definitions; their composition in the caller's
  context determines where a table is needed. A direct runtime enum is split
  when its case can affect applicability: an exact case pattern or a value
  qualifier needs that fact. A method body can also require the case to keep a
  type-valued intermediate result comptime-known, as in the DWARF reader's offset type.
  Generic methods otherwise retain runtime enums; their nested calls can make
  independent case decisions. Twelve independently processed enum inputs do not
  automatically create a table of every twelve-input combination
  ([enum_demand](tests/enum_demand/test.md)). Tagged-union, finite error-set and
  error-union inputs retain eager refinement in this increment. Each needed arm
  uses the same resolver, pointwise specificity, context position, private homes and accumulated
  caller context. An enum-wide fallback cannot hide more specific value methods.
  The selected enum case remains comptime-known within its specialized branch
  and through ordinary calls that forward it. Predicate functions use this same
  mechanism. Method precedence is shared; table construction resolves each case
  under the ordinary rules rather than introducing a separate enum priority.
  This supersedes the former rule that data slots never bridge.
  A comptime-known input selects its arm directly. A needed runtime split checks
  every possible case, selecting only one at execution; argument producers execute
  once before the table, in source order. Earlier facts can rule out methods and
  remove the need to split another input. Interacting enum inputs can still require
  combinations; dependencies through opaque calls and pack results can also be
  conservative. This does not promise optimal table construction. Named inputs and
  fields expanded from splats follow the same coordinate mapping. Packs themselves
  are not recursively scanned: a nested enum becomes eligible for splitting when
  passed as a direct input.
  This is a semantic rule, independent of optimizer decisions; identical arms
  may subsequently fold. It does not add a global method table.
- **Branch facts drive dispatch (RATIFIED principle, 2026-09-15).** A branch
  establishes a fact that ordinary dispatch can use inside the branch. Knowing
  that fact at comptime removes the runtime test; the value itself may still be
  runtime data. An enum arm establishes an exact tag. An interval arm could
  establish membership while leaving the exact integer unknown. Only the enum/
  tagged-union form RUNS today. Known results from a static union arm also survive
  ordinary helper calls and forwarding without suppressing runtime effects
  (RUNS: `variant_static`, corrected 2026-09-17). General fact representation,
  interval patterns and runtime numeric guards remain OPEN; the small range probe expands
  individual values and does not implement symbolic interval refinement. See the
  [scalar dispatch research](design/dispatch_tables.md#the-underlying-structure).
- **Enums and tagged payloads.** A plain enum retains its enum type; the selected
  value becomes a static pack field. `Qual.enum_value = EnumValue(E.tag)` is
  VALIDATED in native method data, above exact input type in the same rank-4
  position as a specific type value. Enum member expressions RUN (2026-09-18):
  `orderType().lt`, or `Order.lt` after a local `Order = orderType()` binding,
  selects an existing member of a known enum type and retains its static value.
  Missing members error. Generic static member access now also exposes native
  namespaces and public constant declarations (2026-09-20). Exact enum patterns
  RUN in source: `offsetType(Format.32) = uint32`, or a named constant bound to
  that case. Member paths and bare defined values resolve at comptime in the
  method's lexical declaration scope, independently of caller overrides. Fresh
  bare names still bind inputs. Calls/arbitrary expressions in signatures remain
  unbuilt, as does dedicated enum declaration syntax. Recognizing native enum/union types for dispatch
  does not ratify enum or struct declaration keywords in jpp. A tagged union
  instead supplies `Variant(U, tag)`, with a
  `.payload` field and type metadata retaining its owning union and tag. Methods
  can group variants using ordinary predicates; `jpp.isVariantOf` and
  `jpp.isVariant` are reflection helpers usable in ground predicates. Native
  variant identity is checked by re-application; forged metadata is insufficient.
  Fresh where-bound types describe the refined variant. A bare `::U` native
  exact-type signature is not a variant-family predicate; use an explicit family
  predicate to cover U's variants. The wrapper is a shallow value copy, not a
  mutable view or an ownership transfer. References inside payloads retain their
  ordinary lifetimes. No enum/union declaration is duplicated in the serializer.
- **Enums are a tight Zig wrapper (RATIFIED direction, 2026-09-19).** The enum
  interface belongs in an ordinary jpp library. Zig supplies the actual type,
  cases, tag representation and layout; wrapping an existing enum must preserve
  that type's identity and its values. There is no second enum definition to
  maintain or required runtime container around each value. Shared dispatch
  behavior for enums and tagged unions does not require a new case-family
  representation. The library exposes native facts; ordinary jpp methods
  compose the behavior whose unresolved choices become implicit switches.
  Investigate generic native primitives beneath jpp-only wrapper bodies, starting
  from composed source examples. The wrapper API and primitive set remain OPEN.
  Base.Zig now supplies the namespace root through one native ground; generic
  member access replaces the enum-only lookup. Table injection still lives in
  `src/jpp.zig`; moving its policy into jpp remains future work. See the
  [wrapper boundary](design/dispatch_tables.md#native-types-jpp-wrapper).
- **Value qualifiers (RUNS, 2026-09-20).** A guard such as
  `label(level::Level) where needsAttention(level) = "ATTENTION"` calls an
  ordinary predicate on the known case established by dispatch. A classifier
  can instead be compared explicitly:
  `panel(level::Level) where destination(level) == "operator" = "ALERTS"`.
  These are boolean expressions, evaluated at comptime in caller-first context
  with the method's declaration home available. Guard calls are lexical
  dependencies even in unused methods and survive context collapse.
  Member paths rooted in known module values must also exist, even in unused
  guards or ordinary bodies. This check does not execute calls or read parameters.
  Each condition refines one fixed input; comma-separated conditions can refine
  separate inputs or conjoin constraints on one. Guards run after structural
  binding and existing type gates. Unknown runtime scalar or payload values cannot
  decide a guard; their known type facts can. Tagged-union type/tag classifiers may
  use ordinary jpp helpers without reading the runtime `.payload`; native
  predicates require known inputs.
  A parameter name still denotes its value: `source::int64` does not make
  `predicate(source)` mean `predicate(int64)`. Comparing argument types requires
  an explicit type query or bound type names. General multi-input expressions,
  including predicates on two known bound types such as `sameType(T, S)`, remain
  an implementation gap; the unary restriction is not a desired language limit.
  No runtime producer or side effect is executed to determine applicability.
  Within the same base input domain, guarded methods outrank the unguarded
  default. Exact enum/error cases outrank a guard on their wider native type.
  Conjunction and direct authored order between predicate words refine guarded
  methods pointwise. Distinct expressions without a known relationship remain
  incomparable; no logical implication is guessed from arbitrary function bodies.
  The base specificity ladder remains in force: a guard on a bare binder does
  not automatically outrank a more constrained type annotation.
  `Base.Equality` supplies ordinary `==` methods for strings, same-type scalars,
  native enums and native errors. `isOneOf(value, cases...)` is an ordinary
  variadic membership predicate; callable predicate factories remain unbuilt.
  Existing `where T == S` between type binders retains its authored mutual-order
  meaning. Value comparisons and body expressions use the ordinary `==` word.
  Integer/float threshold predicates also work when the input is explicitly
  known, as in [sensor configuration](tests/value_guard_static/test.md).
  Correlated multi-input guards, whole-rest guards, callable values and runtime
  integer/float thresholds remain OPEN. See [log_labels](tests/log_labels/test.md).
- **Native errors (RUNS, 2026-09-20).** An error-set alias such as
  `ReadError = Zig.std.Io.Reader.Error` preserves the native set. A qualified
  member must already belong to it; a missing member never becomes a binder.
  Errors with the same name retain their shared Zig identity across sets.
  A narrower native error-set annotation refines a superset annotation; an exact
  error case refines both. A direct `E!T` argument injects success/error branches:
  the success method receives `T`, and error methods receive known native errors.
  Further enum/union refinement of the success payload composes normally.
  Nested error-union inputs expose their alternatives recursively; forwarding
  those leaves through `identity(value) = value` can merge error layers. Native
  nested results returned by selected methods retain their compatible layers.
  Handling, forwarding or returning an error is explicit; dispatch does not
  introduce an early return from its caller. Runtime `anyerror` cannot supply
  a closed table and is rejected; a known error value can be narrowed and used.
  Native tagged unions remain the representation for payload-carrying sum types;
  this increment does not add a separate `Sum(...)` constructor.
- **Table obligations and scope.** Every possible runtime arm must resolve;
  missing coverage and competing maxima fail during compilation. A known static
  tag requires only its selected arm. Runtime arms must share a return type, or
  return variants that rejoin their common owning union (so `identity(x) = x`
  works). Compatible success/error results now rejoin native error unions and
  combine their finite error sets. General numeric promotion and unrelated
  successful result joins remain unbuilt; a runtime-selected type cannot escape.
  A type selected and consumed within a specialized body remains comptime-known.
  Non-exhaustive enums can pass through generic code; they are rejected when
  runtime splitting is requested. Bool/integer-range splitting is not
  activated by this change; range arms remain a separate probe. `resolve` itself
  resolves a refined leaf pack; `call`, return inference and delegation inject
  tables. General surface braces and patterns beyond defined type/enum/error values
  remain future work.
  Evidence: native enum/delegation/ledger tests, `enum_demand`,
  `enum_guard_runtime_ambiguous`, `variant_dispatch`, coverage/result rejection
  cases, and the modular [JSON case study](tests/json_dispatch/test.md).
  The [design walkthrough](design/dispatch_tables.md) shows shared scalar and
  container definitions, recursive traversal and independent policy modules.
- `<:` has ONE meaning, defined by desugaring: "the TYPE BINDER on my
  left satisfies the predicate on my right" — it never applies to a
  value. The argument-position form introduces an anonymous binder:
  `x<:Integer` ≡ `x::T where Integer(T)` (T fresh = typeof(x));
  `{T<:Integer}` ≡ `{T} where Integer(T)`. So the apparent asymmetry
  (braces constrain the binder itself, parens constrain the argument's
  type) is not notational — every `<:` reduces to a where-clause over a
  type binder, aimed at what dispatch SEES in that slot. Rank is
  carried by the symbol: `::` exact (3), `<:` predicate (2), bare (1) —
  which is why `T::Integer` is ill-formed: `::` takes a TYPE on the
  right (exactness / kind), `<:` takes a PREDICATE; letting a predicate
  follow `::` would both hide rank and resurrect the type/predicate pun
  the no-puns rule exists to prevent.
- Brace-only functions are called without parens: `promote{A, B}`.
- Free type variables in the arg list (`a::A, b::B`) bind implicitly.
- `typeof(x)`: the type of a value, as a comptime value.
- Blocks are `{ ... }`; the last expression is the value; a bare comma
  expression returns a tuple; `t...` splats a tuple into arguments
  (julia's spelling) — the dual of building one.

## 5. Reflection

Two comptime primitives:

- `exists(f, args...)` — does this call resolve for these comptime-known
  values in this context? (also spelled over call shapes:
  `exists(promote{A, B})`)
- `ret_type(f, args...)` — the return type of the resolved method,
  propagated back from the surface bits' declared return type.

Both are memoized (free via Zig's comptime call cache);
`exists` is **cycle-answers-false**: resolution re-entering
the same key while in progress answers false (no self-supporting
derivations; same rule as Rust's inductive trait cycles, arrived at via
the `recursion_free` pattern from Signals.jl). Prefer domain constraints
over reflection guards where the rule table is total (see the future numerics design
operators: `where A <: Real`, not `exists`-guards).

## 6. Lowering — braces, `call`, `resolve`

The whole surface reduces to one mechanism:

- **Brace application is Zig generic instantiation.** `F{t1, t2}` is a
  comptime function on comptime values, lowered to a generic Zig struct
  (`fn F(comptime t1: type, comptime t2: type) type`). Its result is a
  comptime value — often a type — and when that type carries a `call`,
  `F{...}(args)` is `F{t1, t2}.call(args)`: braces evaluate away at
  comptime; parens are the real code left standing when comptime ends.
- **Every surface call lowers to `call`.** `f(args...)` written in
  module M means `call{M's context, f}(args...)`, defined in core:

      call{context, f}(args...) = resolve{context, f, typeof(args)}(args...)

- **A signature is a pack CONSTRUCTOR (ratified).** `{x::T, y::S} where
  P{T,S}` emits as ONE comptime function: bind the pattern's variables
  from the candidate pack, evaluate the where predicate, and either
  return the refined pack type (bindings carried as decls — the body's
  `T` is a decl access, no environment machinery) or DECLINE.
  `matches` = "constructor succeeds" (`Sig(Args) ?type`, null = soft
  no-match: where clauses participate in dispatch, so refinement
  failure is not an error — only an empty candidate set is). Same for
  the runtime pack: values arrive at runtime, the pack type is still
  constructed at comptime. This is refinement typing via smart
  constructors — precisely how Zig's own generic types behave.
- **`resolve` is the only magical external.** `resolve{context, f,
  ArgTypes}` is a comptime function over the context's ordered method
  sets, returning the one callable instance (rank first, position on
  ties). Memoization and cycle-answers-false live inside resolve;
  `exists` is its question form. Everything else in the language —
  promote, convert, the operators — is library code above it.
- **Every function is `f{context} -> function`.** Two comptime
  indirections: resolve picks the method, instantiation specializes it
  per (context × argument types). Both are memoized by Zig's comptime
  call cache; both evaporate at runtime. Instances for the same function
  under different contexts coexist in one binary (validated: wrapping
  and saturating `double` side by side in `spike/`).
- **The unit ladder (ratified).** Unit of computation: the
  context-resolved call. Unit of meaning: the method (name, home module,
  slots, where, body). Unit of organization: the module (ordered
  method-set + usings). Unit of compilation, caching, and invalidation:
  the instance — method × context × argument types.
- **A program has two representations.** Statically it is just
  `[]Module` — deliberately NO whole-program structure, no global call
  graph, nothing to keep consistent. Dynamically the program is the
  INSTANCE GRAPH: nodes are instances, edges are resolved calls, grown
  lazily by Zig comptime from the single seed `main{CTX}` — the graph
  IS Zig's comptime memoization table, so it is derived, never
  represented. Sealing closes it (the binary is its reachable nodes);
  incremental invalidation flows through its edges toward callers (the
  signals analogy); the on-disk cache is content-addressed on its node
  keys. Thorin/MimIR keep the sea-of-nodes as a concrete structure
  because the IR is their product; jpp's sea lives as a memo table
  inside the Zig compiler, rent-free.
- **The surface form is julia's `Expr`, ratified.** An expression is an
  ATOM (symbol | literal | ground block) or a HEAD plus children —
  julia's head vocabulary verbatim where julia has one (`:call` with the
  callee as first child, `:curly`, `:block`, `:tuple`, `:if`,
  `:assign`, `:typed`, `:<:`, `:where`, `:for`); ground blocks are the
  one new atom (lexer captures the body raw). Two deliberate deltas from
  julia: heads are a CLOSED enum (exhaustive reader switches; macros
  would arrive via a macrocall head, never new heads), and every node
  carries its source SPAN — JuliaSyntax's lesson, learned from julia's
  own decade paying for LineNumberNode provenance. There is no Stmt
  type: a bind is an `assign` node, a body is a `block` Expr. Exactly
  THREE representations, each one producer one consumer: Expr (parser ->
  reader) -> Method (reader -> normalizer) -> FlatBody (normalizer ->
  emitter).
- **`{}` disambiguation (ratified, lexical, no lookahead):** `IDENT{`
  juxtaposed = curly application (julia's own `f{T}` rule);
  `zig{`/`c{`/`llvm{` = ground atom; otherwise block.
- **The macro door stays open, cheaply.** Expr as a jpp comptime value
  means macros would be comptime `Expr -> Expr` functions under ordinary
  dispatch. Execution venue deliberately deferred — three viable paths:
  transpiler-side mini-interpreter (macro bodies are comptime-only
  code); compile-then-load bootstrap (MimIR's plugin move); or the
  Futamura route — a Zig comptime interpreter specialized on a
  comptime-known Expr tree IS compiled code (CTRE precedent). The
  uniform layer is what keeps all three possible.
- **Parser bootstrap:** JuliaSyntax.jl parses essentially all of jpp
  after (a) pre-extracting ground blocks, (b) rewriting
  `:braces`/`:bracescat` -> `:block` — usable to cross-check our parser
  and generate a test corpus before it exists.
- **Bodies normalize to A-normal form.** The nested expression tree is a
  parse artifact. The normalizer flattens every body into a linear op
  vector — each op is `id = op(operand refs...)`, operands are only
  references (param / earlier id / literal / context name), user binds
  alias an id and vanish, the body's value is one final ref. Ternary is
  a `select` op carrying two regions (flat sub-bodies) — flatness is
  recursive, not global. Pipeline: parse -> tree -> normalize ->
  FlatBody -> emit Zig. Comptime rewrites, if ever, operate on FlatBody.
- **Immutable local bindings (RUNS).** Inside a body block, `name = expression`
  names the expression's value. Later uses alias the same ANF reference:
  a call executes once even when its result is used several times. Literals,
  runtime records, parameters, and type-valued results can all be bound.
  Bindings are sequential and immutable within a method; a name cannot be
  read before its initializer or replace an existing local, input, or
  where-bound type. Blocks group expressions without introducing another
  binding scope, and return their last expression's value. `_ = expression`
  discards a result while preserving its effects and can be repeated.
  An explicit local binding can shadow a module word as a value; applying
  local callable values is still unbuilt and produces a diagnostic rather
  than dispatching to a same-spelled module word. Typed local annotations
  and mutable assignment remain outside this implemented surface.
- **Overridable definition operator (RATIFIED direction, 2026-09-18; unbuilt).**
  The eventual `=` word covers both value bindings (`x = expression`) and method
  definitions (`f(x) = body`). The agreed protocol dispatches on the kind of
  definition target and a scoped, unevaluated right-hand side; a method body is
  stored for later execution. The default binding behavior can retain immutable
  names and single evaluation. This does not make the current parser or normalizer
  extensible yet. Handler selection context, bootstrap and detailed staging rules
  remain OPEN; see the [definition protocol](design/generality_plan.md#definition-as-a-dispatched-operation).
- **The unit of computation is the call** (reference: Thorin/AnyDSL,
  "A Graph-Based Higher-Order IR", CGO'15). After definition elaboration,
  the default immutable binding names a data edge and is erased at emission (jpp
  bind -> Zig `const` -> LLVM SSA). Bodies-as-statement-vectors are
  surface sugar over a dataflow graph whose only computing nodes are
  context-resolved calls and ground axioms (Thorin's primops). We adopt
  Thorin's semantics but not its machinery: their lambda mangling /
  lower2cff (specializing static and higher-order parameters until the
  program is first-order) is exactly what Zig comptime instantiation
  does to our `ctx` parameter — so the graph IR, the scheduler, and the
  specializer are all delegated to Zig + LLVM. `var` (mutation) is NOT
  edge-naming — parked with the memory model.

## 7. Ground zero — `zig{ }`, `c{ }`, `llvm{ }`

jpp bottoms out in Zig: builtin machine types ARE Zig's (`int64` = `i64`),
and anything Zig compiles to is a seal target (x86/ARM/RISC-V, WASM,
freestanding; Zig ships clang, so `c{}` is native, not FFI).

Boundary contract:
- The jpp signature is the contract: param names flow in. The return
  type: declared wins when present; otherwise INFERRED across the
  boundary. RUNS: the ground's generated `run` return signature analyzes
  the body with `@TypeOf` against its runtime parameters; the separate
  return query asks for that function call's type without executing it.
  Runtime record fields stay runtime, while explicitly static fields
  retain their values and type identity (`ground_records`).
  Same rule as jpp-level bodies — one inference story everywhere.
  This replaces the undefined-comptime-pack mirror, which incorrectly
  froze record data and tried to evaluate runtime branch conditions.
  Runtime selection now infers correctly. Zig operations that inherently
  require comptime data still cannot depend on runtime values.
- Ground blocks see the module's own declarations (their emitted Zig forms).
- Bodies are axioms — no context dispatch inside. One-way door.
- **Axioms are enumerated, not predicate-generic**: ground methods are
  defined per concrete type (in comptime loops), never as
  `f(x<:Integer) = zig{...}` — an axiom must not silently cover types it
  was never written against. Predicate methods are for jpp-level code.
- Target selection is ordinary dispatch on comptime values: `ARCH` (from
  `intrinsics.jpp`, itself read from Zig's `@import("builtin")`) passed
  as an argument; `_f(..., ::arm64)` beats `_f(..., T::type)`.
- `llvm{}` ties instances to the LLVM backend (fine for leaf modules;
  the fast incremental dev loop prefers `zig{}`).

## 8. Numerics (julia-9/10 decisions)

- **Integer overflow wraps** (two's complement, Julia semantics):
  ground ops are `+%`/`-%`/`*%`. A `checked_ints` policy module can
  offer trapping arithmetic to contexts that import it.
- **`convert` is exact** — lossy is an error (`InexactError` semantics);
  identity is `convert{T}(x::T) = x` in `core`, an exact match that
  outranks every predicate method (extenders need no self-exclusion guard).
- **`promote` is one name, two call shapes**: brace call `promote{A, B}`
  on types returns ONE type (Julia's `promote_type`); paren call
  `promote(a, b)` on values returns the CONVERTED PAIR (Julia's
  `promote`). The slot separates what a name pun couldn't.
- Promotion rules are Julia verbatim, and live with their type owners:
  ints own same/mixed-signedness (`int32+uint64 -> uint64`), floats own
  float×float, `reals` owns cross-domain (ints dissolve into floats).
- Promotion is not language magic: the promoting operators are ordinary
  generated methods in a future numeric library ([design](design/numerics.md)). A context that doesn't import them
  has no mixed-type arithmetic. Rigor variants (e.g. `strict_promote`)
  are context choices, not forks.
- In-family `convert` lives with the family; cross-domain in `reals`;
  ownership discipline throughout: rules live with the types they serve.

## 9. Compilation model

- **jpp is a transpiler, nothing more.** The meta-compiler reads jpp,
  emits Zig comptime code, and `zig build` does everything else. No IR
  of our own, no codegen, no linker, no runtime resolver.
- **The transpiler's whole job: parse -> ANF -> print.** Parse to the
  surface tree (the only real new code), normalize to FlatBody
  (mechanical), print Zig from fixed templates validated by `spike/`.
  From there everything is comptime: resolution, specialization, context
  propagation, the instance graph, DCE, invalidation. The transpiler
  never resolves a call. Remaining real work, in effort order: the
  parser; diagnostics mapping (Zig comptime errors -> jpp lines); source
  provenance in the printed Zig (decide day one — painful to retrofit).
- **Mangling-free naming via `@"..."`.** Zig accepts any string as an
  identifier, so jpp surface names transpile verbatim: `pub const @"+"
  = jpp.MultiMethod("+", .{...})`. Unquoted identifiers are reserved for
  machinery (`resolve`, `call`, `rank`, `matches`, `Ret`). One word,
  one decl: `@"promote"` binds brace and paren senses alike — the pack
  type distinguishes them (one-pack ratification, §4).
- **A transpiled method is FIVE FACTS, all data (ratified —
  supersedes the v1 function-emitting shape below):**
  1. `name` — the name this method gives a sense to.
  2. `signature` — the args structure, as a comptime datum: selector
     slots, positional slots, named slots, quals and patterns, the
     declared return, and the `where` gate (part of the constructor).
  3. `body` — a vector of Expr in A-normal form (`id = call(name,
     refs...)` — the FlatBody layer), OR raw ground source
     (`zig{}`/`c{}`/`llvm{}`) for axioms; ground-ness is the body's
     tag, not a flag.
  4. `hash` — content hash over the normalized body vector (not source
     text: reformatting invalidates nothing).
  5. `span` — source range, for mapping comptime errors to jpp lines.

  Everything else is a BYPRODUCT, computed by the machinery, never
  stored: rank (derived comparing signatures during resolution),
  construction/bound-pack (the signature interpreter), switch arms for
  runtime selectors (read off the signature's patterns), printable
  signatures for diagnostics, and return types (declared: in the
  signature; inferred: type-walk of the body vector). Per-method
  functions (`bind`, `bindValues`, `Ret`, `call`) are replaced by ONE
  interpreter each in the runtime library: the signature interpreter
  and the body interpreter (a comptime-unrolled `inline for` walk of
  the op vector — compiles to the same code as hand-written Zig).
  Axioms in the machinery, data in the modules; a transpiled module
  approaches a pure data literal. VALIDATED: `spike/interpprobe.zig` —
  ground axioms from data, ANF bodies executed by comptime-unrolled
  interpretation, exact-beats-bare with rank computed on the fly,
  named record section, inferred returns via the type-level walk.
  The specificity POLICY is a SHADOWABLE WORD (`specificity`), not a
  fixed rule: resolve only collects successful constructions and asks
  `policyOf(ctx).moreSpecific(ctx, a, b)` (strict; false on equal AND
  incomparable, so both fall to position). The ground default is
  pointwise dominance: a displaces b iff >= in every slot and > in at
  least one, computed on per-pack PROJECTIONS (exact type value 4,
  exact input type 3, predicate 2 —
  including ranges and single-binder where-conjuncts, bare 1,
  with fixed coverage before rest coverage; tuple by position, record by
  name, selectors as ordinary slots). A strictly narrower structural pack shape
  breaks otherwise equal supplied coordinates. At equal predicate rank, an absent edge means
  incomparable, not equal. One better coordinate cannot compensate for
  another incomparable coordinate (`pointwise_gap`). For conjunctions,
  every required gate must have a direct witness from the other method's
  gates; their written order is irrelevant (`gate_conjunction`).
  Sum and lexicographic were considered and rejected
  (sum launders incomparability into arithmetic; lexicographic makes
  argument order a specificity axis). Equal-or-incomparable overlap:
  within one module = comptime AMBIGUITY ERROR AT THE CALL SITE —
  julia's exact venue (the manual: definition order does not matter,
  ambiguity may coexist harmlessly "if transiently" until a call hits
  it; the fix is the intersection method, which then dominates both) —
  implemented in resolve as a maxima computation: collect all
  constructing candidates, keep the non-dominated; two maxima in the
  position-winning module = error listing candidates; maxima across
  modules = context position (the ordered context doing its ratified
  job — validated: crossings flip with context order, dominance still
  beats position). Julia patterns validated against src/jpp.zig: the
  manual's g-crossing (error in one module — verified negatively;
  position across two),   manning's 4-method `bar` lattice (every cell
  by dominance, intersection kills the ambiguity), aqua.jl's
  mixed-rank crossing ((3,2) vs (2,3) — incomparable by STRUCTURE
  where sum would fake a 5=5 tie), and the exact>pred>bare ladder.
- **The order is a type-only word: `<:` (RUNS).** Both arguments are
  type values and the answer is Boolean. Concrete types and the class
  identities of defined predicate words use the same call machinery.
  An authored relation refines overlapping dispatch candidates; no prover
  checks inclusion, and no transitive closure is implied.

  - A fact is `<:(Signed, Integer) = true` with both names defined or
    imported. A negative fact uses `false`. A generic rule can consume
    named inputs, for example `<:(P::type, Q::type) = same(P, Q)`, or
    explicitly ignore them: `<:(::type, ::type) = false`.
  - Identity is an unshadowable floor. Otherwise ordinary specificity
    selects a method, with context position breaking ties across modules.
    A specific fact therefore beats a general rule even when the rule's
    module appears first. A missing pair returns false. Direct queries
    and predicate-order comparisons share these rules.
  - Order resolution uses the stratum-0 rank ladder, without consulting
    the order or a shadowable specificity policy. Equality gates derived
    from `<:` are rejected on `<:` itself. This breaks resolver-induced
    recursion; arbitrary cycles through user bodies/predicates still need
    the planned in-progress handling (§11). The legacy ground `OrderRule`
    probe is more restricted: its function signature cannot receive a
    context. That guarantee does not apply to arbitrary surface bodies.
  - All comparisons are direct. With A<B and B<C, candidates at all three
    can leave A alone maximal; removing the B candidate can expose an
    A/C ambiguity (`lattice_gap`, `collapse_dependencies`). A caller can
    supply the missing A<C edge (`lattice_bridge`).
  - A mutual pair gives equal priority for that pair and satisfies a
    `where T == S` gate. It does not change structural type identity or
    establish transitive equivalence. A strict three-way cycle can leave
    no maximum; this is diagnosed as cyclic strict order (`order_cycle`).
    Earlier claims that every cycle forms a quotient type were too strong
    for the explicitly pairwise language.

  Equality and predicate gates both receive caller-first context extended
  with the declaring module's imports (`equality_scope`, `folder_scope`).
  `specificity` and `<:` declarations survive context collapse. The Zig
  `Edges`/`OrderRule` APIs remain as the legacy probe representation;
  generated source uses ordinary methods with exact type-value constraints.
  Their tables do not establish that surface membership is inferred from
  an order fact: membership still comes from the predicate body.
  LITERAL-HEAVY WORDS COMPILE TO TABLES (ratified): `<:` will carry
  MANY literal declarations (numeric tower, user domains, comptime-for
  generated families). A population of bodiless exact-value facts is
  semantically a lookup TABLE — mutually disjoint by identity, trivial
  dominance, constant bodies — so the compiled form is an ordered
  per-module table, unioned through the context, first hit wins
  (implements shadowing/position exactly). The v1 `Edges` encoding IS
  this table. The future optimization would detect
  all-exact-fact populations and emit them back down to tables:
  surface methods, table physics. Third face of "selection all the way
  down": switch tables (runtime closed domains), fact tables (comptime
  pairs — `promote{A,B}` is the same shape, julia's promote_rule),
  method tables (open dispatch). Cost: memoized once per (P,Q) per
  build regardless of table size. COST: `<:` is the most heavily used
  operation in the system and is never inferred — point evaluation
  (`P(T)`, dispatch-hot) or edge lookup (authored facts), both
  memoized by zig's comptime call caching: each distinct question
  (predicate × type; word × context × pack) is answered ONCE per
  build. Compile time scales with distinct questions, not with call
  sites — which is why context collapse (memo-key normalization) and
  the .so symbol cache (skip comptime for compiled instances) are the
  two levers that matter. The failure mode is cycles, not volume
  (§11 landmine). ENTITLEMENT PRINCIPLE: importing grants standing to
  shadow — methods AND decisions; a context that leads with a policy
  module gets different dispatch decisions for the same call
  (validated). Circularity break, same as §3: THE JUDGE IS CHOSEN BY
  SENIORITY, NOT BY JUDGING — the policy word is selected by position
  only (first module in context declaring it; ground default last),
  because specificity cannot be used to select the specificity judge.
  Tooling contract (proposed): the resolver never casts (binding never
  converts — promotion is a visible library method at predicate rank,
  julia-style, never a resolution rule); every position-decided
  resolution is seal-time auditable (the ambiguity ledger) and
  explainable from signature data.
  - `jpp.MultiMethod("name", .{methods...})` — pure ENCAPSULATION: it
    binds all definitions of one word in one module, in definition
    order, and stamps `is_jpp_multimethod` (so the resolver can skip
    unrelated decls that merely share the name). It chooses nothing —
    resolution policy lives whole in the ground resolver, never split
    into the encapsulation. A module's entry is its CONTRIBUTION to a
    word's meaning; the meaning at a use site is the context-fused
    view, which exists only per instantiation — so anything
    presupposing a complete meaning (ambiguity checks, coverage,
    sealed tables) belongs to (word, context), never to this struct.
  - Historical: v1 emitted per-method structs with
    `rank/matches/Ret/call` functions. Its emitter and demos are retained in
    git history. The active compiler uses the five-facts data shape;
    `spike/jpp.zig` retains the old encoding solely for the tail-call probe.

  Module -> Zig struct (a file) with `@"name"` MultiMethod decls;
  context -> comptime tuple of module structs; surface call
  `f(args...)` -> `jpp.call(jpp.extendAll(ctx, STATIC), "f",
  .{args...})`. Dispatch branches emitted into runtime functions must
  be `comptime`-forced (`if (comptime P(T))`) so dead branches are
  pruned, not analyzed.
- **The transpiler is file-local and context-blind.** It emits only what
  the file alone determines: the module's STATIC tuple (from its `using`
  lines), `comptime ctx` as first parameter of every function, and the
  `extendAll` merge at call sites. It never computes an effective
  context — it can't, the caller chain isn't known. ALL context
  propagation happens at Zig comptime, per instantiation: generic
  functions are analyzed lazily, so modules compile standalone before
  any caller exists, and each new calling context is just a new
  instantiation. Consequence: dispatch errors surface as Zig comptime
  errors at instantiation; the front end's diagnostic job is mapping
  them back to jpp source.
- **No CPS at runtime — and neither has Thorin.** Thorin lowers its CPS
  to control-flow form before codegen; jpp never enters CPS at all: ANF
  + select regions are direct style, Zig/LLVM build the CFG. What we DO
  take: guaranteed tail calls. The emitter marks tail-position calls
  and emits `@call(.always_tail, ...)` — a CHECKED guarantee (compile
  error where target/signatures can't, never silent stack growth).
  After monomorphization signatures are concrete, so the musttail
  compatibility check is decidable at emission. Validated end-to-end
  through the full method-struct encoding: `spike/tailcalls.zig`, 10M
  mutual even/odd calls through resolve, debug build, 13ms. Payoffs:
  the promoting operator's re-entry is a same-Ret tail call (zero-frame
  wrappers); comptime state machines (regex DFA) are functions + tail
  jumps — MimIR's "state continuations" for free.
- **`build.zig` is the driver — jpp ships no orchestrator.** Zig's build
  system is itself comptime machinery one level up: a Zig program
  computing a lazy, cached build graph. The transpiler is a build step
  (`addRunArtifact`): `zig build` = transpile changed .jpp -> generated
  .zig -> compile, incremental at file granularity via step caching.
  Toolchain surface: `zig build --watch -fincremental` (live session),
  `zig build test`, `zig build seal -Doptimize=ReleaseFast`. jpp the
  product = one transpiler executable + one build.zig template.
- Front end and session runtime written in Zig; jpp transpiles to Zig;
  Zig comptime is the monomorphization engine; `zig build --watch
  -fincremental` is the dev loop; `ReleaseFast` + LTO is `jpp seal`.
- **Tiered compilation (ratified).** Tier 0 — liveness: every instance
  compiles as a CALLABLE with a hard call boundary, no cross-instance
  inlining; callees are already-compiled binaries, so compiling any one
  function is a few lines and edit-to-running is instant. Because the
  compilation-unit boundary IS the instance boundary, an edit
  invalidates only the edited module's instances — callers survive
  binary-identical (they call through per-instance slots; inlining is
  exactly what smears a change across units, and tier 0 refuses it).
  Tier 1 — throughput: a background optimized/inlined build of the same
  generated source; when ready, flip the slots (hot-swap at call
  granularity; next call is fast). Sealing = tier 1 minus the slots.
  Mechanical v1: tier 0 = `zig build --watch -fincremental` (debug —
  function-level patching, no inlining, free); tier 1 = background
  ReleaseFast build; a slot table switches. v2 if needed: per-instance
  content-addressed objects keyed (method hash × context × pack × tier).
- **Semantics are tier-invariant (ratified).** Build mode may affect
  speed, NEVER observable behavior. Safety is a per-operation semantic
  decision in jpp code: checked conversion emits its check in ALL
  tiers; wrapping arithmetic is `+%` in all tiers. Nothing inherits
  Zig's safe/fast build-mode semantics (`@intCast`-style
  traps-only-in-debug is forbidden in emitted code — the check must be
  explicit).
- **The compiler compiles; it never owns the code (ratified).** The
  inversion of the VM/JIT model: in julia, code lives inside the
  runtime and cannot be peeled off its host. In jpp the artifacts are
  freestanding native code at every moment; the compiler is a PEER at
  the edge — it watches sources, produces .so's, probes symbols, fills
  slots — and everything it touches is plain data (pointer tables,
  loadable objects), never a runtime the code calls back into. Its
  absence is not a degraded mode but the same program: sealing resolves
  slots to direct calls and walks away. `--embed-compiler` is the same
  compiler linked into the process, still only allowed to touch slots.
- Everything is native code always. The session runtime exists only for
  liveness: indirection slots for open functions, the invalidation
  tracker, session state, the watching compiler. Sealing removes all four.
- **Selection all the way down (ratified).** jpp is one operation at
  every level: a comptime function choosing among registered
  implementations given a key. Methods: `resolve` over (context, name,
  pack type). Artifacts: the build graph chooses a binary path — cached
  object, prebuilt .so, or source fallback — via ordinary build.zig
  code probing what exists (`findProgram`, `linkSystemLibrary`,
  `addObjectFile`, lazy deps); linking IS resolve at the binary level.
  Tiers: the slot table chooses tier-0/tier-1 per instance per call.
  Seal: the linker chooses the reachable subgraph. Consequence: a
  shipped library is a WARM CACHE — an instance is reusable iff its key
  (method hash × context × pack type × tier) matches what the
  consumer's build derives; mismatch falls through to source, soundly.
  (Julia's precompilation caches break because they are keyed by less
  than what determines the code; these are keyed by exactly that.)
- **Context collapse: the RESOLVING MODULE owns the instance (ratified,
  validated: `spike/interpprobe.zig`).** Accumulated contexts carry the
  whole call path's sediment (A→B→C), but if resolution with the full
  chain equals resolution starting at B, the prefix is dead weight — B
  is the resolving module, and the instance keys to (and is cached in)
  B's context, not the caller's. The machinery canonicalizes BEFORE
  memoization: bodies are data, so the reachable word set is a comptime
  closure (word + body callees, transitively, over all candidates, plus
  the policy word and signature predicate words); modules declaring
  nothing in the footprint provably cannot change any resolution and
  drop (decl-level). RUNS: the active implementation is conservative and
  keeps every module defining a reachable word, including losing methods.
  Discovery follows static imports transitively so a dependency hidden
  behind a later module boundary cannot erase a caller's override early.
  That discovery graph is not the resolution context: collapse only
  filters the existing caller sequence, and imports still accumulate on
  method entry (`collapse_imports`, `checkout`). Worklist discovery and
  cached context values let the checkout graph compile under the existing
  comptime quota; this does not settle the recursion issue in §11.
  A more aggressive decision-based collapse is OPEN. The historical
  probe's claim that removing losers always preserves winners is false
  for the pairwise nontransitive relation: A<B, B<C, no A<C leaves A
  maximal with all candidates, but removing B exposes A/C ambiguity.
  `collapse_dependencies` pins this counterexample. Such an optimization
  must preserve decision dependencies or revalidate every affected
  selection; the existing probe examples do not prove the general claim.
  Consequences: CROSS-BUILD SHARING — an inert caller's chain collapses
  to the library's own context, whose instances the library's build
  already ships (pointer-identical, validated); SHADOWING IS
  PAY-PER-USE — per-caller instances exist only where the caller
  actually overrides something in the footprint; the founding thesis
  costs nothing until exercised. Explicit context-LIMITING as surface
  semantics (hermetic subtrees) is parked — collapse solves the caching
  motivation without touching meaning.
- **The symbol name IS the content key.** Instances export as
  `jpp$<method-hash>$<ctx-hash>$<pack-hash>$<tier>` — the ctx-hash over
  the COLLAPSED context (above), so permuted call paths converge to the
  resolving module's symbol. "Is this instance already compiled in
  that .so" is one dlsym — the dynamic linker's symbol table is the
  cache index; no manifest, no registry.
  Can COMPTIME probe a .so and use-or-compile? NO — comptime is a pure
  function from source to artifact, no I/O, no linking, by design. The
  capability belongs to the substrate that RUNS builds: the session/
  build layer probes via dlopen/dlsym and fills slots (validated,
  `spike/soprobe.zig`); build.zig runs the same probe at build time and
  feeds the answer to comptime via addOptions (extern + link vs compile
  fallback).
- Every module is inherently a C-ABI shared library ("distribute .so
  with source attached").
- Instance cache is content-addressed on disk, keyed by
  `(function, types, context)` — survives sessions; nothing global can
  invalidate it.

## 10. Deviation register (the 1/10 list)

1. **No global method table** — context dispatch, extension-only.
2. **No abstract type tree** — predicates instead.
3. **No runtime `eval`** — staged comptime codegen; integrated compiler
   by opt-in.
4. **0-based indexing, row-major (C order) tensors** — the NumPy world's
   conventions; zero-copy interop with the ecosystem jpp lands in.
   Shallow by construction: indexing is an open function; `one_based` /
   `fortran_order` are ordinary context imports.

Everything else is Julia, deliberately.

## 10.5 Status: the v1 pipeline EXISTS and runs

`.jpp` text -> native binary, end to end (first achieved with the
print/algebra demo):

- `src/jpp.zig` — the runtime library, methods-as-data: signature
  interpreter, body interpreter, dominance policy word, `<:` order
  word, context collapse, delegation, julia-parity ambiguity errors.
  Inline tests cover dispatch, order, binding, visibility, collapse,
  and delegation; `zig build test` also runs the language cases.
- `src/jppc.zig` — the transpiler: lexer (ground capture with
  string-skipping), parser (defs, params, predicate gates, infix
  precedence, blocks), normalizer (ANF), emitter (five-fact data literals + ground fn
  structs with return inference against runtime parameters), driver
  (defaults: tests/dispatch -> gen/, machinery copied alongside,
  harness generated). Source trees are discovered recursively; folder
  aggregates, optional facades, sibling wildcards, public cyclic-import units,
  dotted imports, and the Base namespace are supported. Generated module filenames and Zig aliases use
  the same byte escaping, preserving `Base`/`base` and `a.b`/`a_b` identities
  on case-insensitive filesystems and avoiding driver/runtime collisions
  (`module_encoding`).
- `tests/` — executable language cases replacing the original demo.
  `caller_context` exercises generic arithmetic supplied by the caller;
  `override` and `depth_override` exercise overrides reaching into
  libraries. DEPTH (validated): `shadowed -> stats -> algebra -> +`
  carries a caller's override through two oblivious modules;
  `report(21)` changes from 42 to the sentinel 1000, while the
  unmodified `*` keeps `square(21)` at 441. The ledger's proposed
  "algebra requires from context: +, *" report is RATIFIED, unbuilt;
  it would report dependencies from the footprint closure. Such a report
  is not a checked callable contract; that boundary is now under explicit
  design review in [word contracts](design/word_contracts.md).
- [Checkout](tests/checkout/test.md) is a larger RUNS case: twenty source
  modules price twenty baskets in retail/member contexts.
  Arithmetic comes from explicit Base imports; the member policy changes
  discounts and freight through deeper imports. Basket storage is a tuple and
  the quote is assembled through required named fields with surface projection.
  Local bindings name intermediate results; export-only dependencies now RUN.
  The basket accepts zero/one/many heterogeneous physical and digital lines;
  recursive pricing shrinks its tuple while preserving caller policies.
- [JSON serialization](tests/json_dispatch/test.md) is a second modular RUNS
  case: std.json.Value is consumed through injected variant tables. Four scalar
  variants share one definition; arrays and objects share a container body and
  runtime cursor traversal. Two policy modules specialize strings/integers for
  one writer family, including nested values. Ground code retains std parsing
  and writing primitives; the case is not a complete replacement of std.json.
- [DWARF offsets](tests/dwarf_offsets/test.md) is a scalar RUNS case using the
  native Format and Endian enums. Separate modules choose width and byte order;
  ordinary calls compose both switches. All four runtime combinations, unsigned
  widening, errors, single evaluation and an inner caller audit policy are tested.
  Known cases can produce type values; runtime calls return one native error
  union. The two IO leaves remain grounds, with no hidden callback into jpp.
- [Log labels](tests/log_labels/test.md) uses boolean and classifier guards to
  route real Zig log levels to an operator or history panel, with typed defaults,
  exact-case refinements and a caller's debug policy.
- [File-header errors](tests/error_dispatch/test.md) dispatches on a byte or a
  native read failure, preserves shared error identity, adds a validation error,
  rejoins the native error union and changes one message in a caller context.
- Validated behaviors, from TEXT: exact/bare dispatch, generic methods
  flowing through ground arithmetic per element type, blocks/sequencing,
  literals as typed data, return inference through jpp bodies AND across
  the ground boundary, predicate gates (including `x<:Pred`), composed
  predicates, and caller-authored `<:` facts refining gated dispatch.
  Defined signature values require lexical definitions/imports. Unused,
  unannotated fresh names error; annotated inputs may be unused, and
  anonymous inputs use an annotation (`<:Any` imports the ordinary universal predicate).
  Type values, type results, and bound
  return types preserve comptime identity through ordinary calls. Private
  helpers and folder declaration homes are tested as part of the module boundary.
  `context_flip` pins import-order tie-breaking; `lattice_gap` and
  `lattice_bridge` pin pairwise order and a caller-supplied missing edge.
  The negative cases also enforce ambiguity and export-gating errors.
- V1 scope cuts (deliberate): no selectors/braces or `M.f` delegation
  in the surface (validated in machinery/probes), no promotion,
  no keyword defaults or nominal record declaration syntax; splats/rests
  currently require statically shaped packs, not runtime-length collections;
  reduced internal AST (alignment with src/ast.zig's three layers = debt),
  no spans/hashes emitted yet. General value literals/patterns in
  signatures, type constructors with selectors, and arbitrary static
  evaluation depending on runtime data remain unimplemented. The live
  compiler, native instance slots, artifact identity, and hot swapping
  described above remain design work; changing these dispatch rules does
  not implement that binary development infrastructure.

## 11. Open

- **Generality implementation sequence:** tuples and packs, named arguments,
  varargs, static type application, record/type families, and library
  promotion. The [staged plan](design/generality_plan.md) records current
  machinery gaps, decisions still needed, and test-folder acceptance cases.
- **Callable dependency contracts:** require a source-visible surface for
  body calls while preserving caller-first implementation selection.
  Research favors typed declarations without mandatory catch-all bodies;
  syntax, contract identity/fusion, and generic call obligations remain
  unbuilt. Export-only declarations and lexical checking already RUN. [Remaining contract questions](design/word_contracts.md).
- **Next phase (declared):** the boundary-testing phase — write the
  promise catalog (`tests/README.md`) into executable claims. The
  negative-compile harness RUNS (`expect.err` in a case folder:
  compile must fail and the error must contain the file's text —
  `ambiguity`, `export_gate`). Remaining rows need surface features
  next (`M.f`, braces, varargs). Predicate gates already have
  surface coverage. Once the phase completes,
  decide: THREADING model, and the STANDARD LIBRARY
  strategy — stay on zig std inside `zig{}` (grounds call it directly),
  wrap it in Base words per domain, or rewrite selected
  parts as jpp modules (candidates: the numeric tower is already ours;
  collections and IO are the real question, and the answer interacts
  with the memory model below).
- Memory model (RC+elision vs ownership inference; allocation as a
  context-dispatched open function is the candidate frame). Waits on
  tensor-shaped examples. Reference points: Thorin/MimIR thread an
  explicit machine-state value through effectful ops (`%mem.M`, the
  functional store) — also the frame in which `var` (mutation) must be
  answered.
- Tensors design (`tensors.jpp` is a decision stub). Direction (from
  MimIR's %tensor + julia's broadcast): shapes/ranks as comptime values
  in the tensor type; ops build lazy comptime-shaped expression objects;
  fusion at materialization in library code; one map_reduce/einsum
  normal form so peepholes and autodiff compose.
- `strict_promote`, `checked_ints` policy modules (five-line exercises,
  when wanted).
- ~~Spike to validate~~ **DONE — `spike/` (zig 0.16)**: hand-written
  emission target for main.jpp. `resolve` as a comptime fn over `@"..."`
  method sets works; specificity ranking works; context threading works
  (promoting operator re-enters `jpp.call` with the caller's ctx and
  same-type calls land on exact ground methods); julia promotion rules
  verified end-to-end (`i32+u64 -> u64`, `u8*u8` wraps, cross-domain
  `i64+f64 -> f64`). Whole pipeline compiles+runs in ~1.6s cold.
  Second pass validated the ordered-context semantics: rank-then-position
  resolution, context accumulation (`extendAll`), and caller override
  reaching inside library code (`checked` shadows ints' ground `u8 +` at
  equal rank; `lib.double`, which never imported checked, wraps under the
  base context and saturates under the checked one — both instances in
  one binary). Still open from the spike: rework to the one-pack
  interface (brace senses become comptime pack fields — designed in §4,
  spike still inlines promote{}/convert as comptime fns and dispatches
  on an ArgTypes slice — an interface that also cannot see comptime
  field values, so the enum bridge forces the rework), the ground
  matcher with context-resolved predicates (§3), per-arg lexicographic
  specificity (spike sums ranks), within-module ambiguity check
  (transpile-time), rebuild-latency-as-REPL measurement at realistic
  module counts. Validated separately: value dispatch + runtime enum
  bridge (`spike/enumprobe.zig`); the binder — two-section packs, no
  cross-fill, permuted named args converging to one instance
  (`spike/binderprobe.zig`); parametric type-words with pattern
  binding and re-application provenance (`spike/vecprobe.zig`);
  methods as pure data with the signature + body interpreters and the
  isolated specificity seam (`spike/interpprobe.zig`).
- **RISK (found via tailcalls spike, zig 0.16): mutual recursion through
  `resolve` is a compile-time landmine.** A 60-line file with two
  methods that resolve each other takes ~2 MINUTES to compile (llvm and
  self-hosted backends alike; one variant ran 11+ minutes before being
  killed). Bisected cleanly: plain mutual tail calls fast; generic
  mutual recursion fast; `@call` + generics fast; method structs with
  DIRECT sibling references fast; SELF-recursion through resolve fast;
  interning the arg-type slice does NOT help. The trigger is precisely
  a mutual instantiation cycle passing through resolve's comptime
  evaluation. Runtime output is correct and fast — only compilation
  pathologizes. `spike/tailcalls.zig` is the minimal repro (file a zig
  issue). Mitigations to explore: restructure resolve (comptime fn
  shape/memo keys); emitter detects recursive SCCs and pre-resolves
  in-cycle edges; or Option A (front-end resolves) for in-cycle calls.
  This is the first hard evidence in the Option A vs Option B question.

## 12. Related work

- **Thorin** (Leißa, Köster, Hack — CGO'15, AnyDSL): graph-based CPS IR,
  blockless, scopeless, no assignments — the call is the only unit of
  computation; "assignments" are call-site parameter bindings (SSA↔CPS)
  or floating data nodes. jpp adopts the semantics (§6: binds are
  edges), delegates the machinery: their lambda mangling / lower2cff
  (specialize static & higher-order params until first-order) is what
  Zig comptime instantiation does to our `ctx` parameter.
- **MimIR** (Leißa, Ullrich, Meyer, Hack — POPL'25; Thorin's successor,
  rebuilt on the Calculus of Constructions): three independent
  convergences with jpp — (1) "axioms": declared signatures with no
  implementation in the IR, meaning supplied externally = our ground
  methods; (2) curly braces mark the static/implicit parameter group,
  separate from value args = our `f{T}(x)` slots; (3) their
  %core/%math/%mem plugin catalog (overflow modes, IEEE strictness
  modes, explicit machine state) mirrors our module/policy catalog.
  What we take from it: the normalization lesson, jpp-natively — keep
  domain constructs as COMPTIME DATA as long as possible, normalize in
  ordinary library code, lower late via staged codegen (regex -> DFA at
  comptime, CTRE-style; tensors -> lazy shaped objects fused at
  materialization, julia-broadcast-style, map_reduce normal form).
  What we reject: extension by compiler plugins (C++ passes against the
  IR's API). jpp extension is only ever modules in contexts; everything
  below comptime is delegated to Zig/LLVM. MimIR is what you build when
  the IR is the product; jpp outsources the IR. The price, named: no
  rewrite layer over runtime expressions — user code is Zig code, not
  data, so all domain optimization must happen where code is still
  comptime values.
