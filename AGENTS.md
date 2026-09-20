# Working on jpp

Read `RUNNING.md` for commands and layout, `README.md` for the language
decisions, and `tests/README.md` for executable promises. Zig 0.16 is the
only build dependency. The repository's Codex defaults select GPT-6 Astra
with `xhigh` reasoning; model selection does not change the compiler.

## Design and implementation

The README is a design ledger. Distinguish RUNS (surface implementation),
VALIDATED (machinery or probes), RATIFIED (decided but unbuilt), and OPEN
(undecided). Check the current source and tests before claiming a feature
works. Report documentation conflicts and update status when implementing
a feature; preserve the ratified semantics unless the task changes them.

- `src/jppc.zig` is the active transpiler: lex, parse, read, normalize,
  and print Zig data literals. Keep parsing/normalization file-local and call
  semantics context-blind; module graph assembly handles paths, facades, and
  import-cycle units.
- `src/jpp.zig` owns dispatch, binding, context accumulation, specificity,
  and the order word. These execute at Zig comptime in generated code.
- Preserve caller-first accumulated context, pointwise dominance rather
  than summed ranks, context-position tie-breaking across modules, and
  ambiguity errors at calls with competing maxima in the winning module.
- A defined/imported name in a signature refers to its existing value; a
  fresh name binds an input. Never manufacture class identities from
  undefined names. Annotated inputs may be unused: their annotation gives
  them a signature role. Unused, unannotated inputs error, including `_`;
  `Any` is an ordinary Base predicate: import it and use `<:Any`, with
  ordinary predicate rank and authored order. Never special-case its name,
  input acceptance, or return type in the compiler. Type values retain their
  identity in comptime pack fields; an integer value and its type are
  different call arguments.
- Private helpers are lexical; exported words fuse through caller context.
  Preserve a method's declaration home when aggregating folders.
- The `<:` order is authored and queried pairwise between candidates.
  There is no implicit transitive closure. A negative test demonstrating
  a missing edge is a language promise, not a resolver bug.
  Mutual pairs do not imply a transitive equivalence relation. Keep losing
  candidates needed for other dominance decisions during context collapse.
- `Base/` supplies qualified library modules. Imports are explicit: `using Base`
  selects Base/Base.jpp's facade, including Any; `using Base.Arithmetic` narrows
  the interface. Source paths can shadow bundled paths. `using Folder` uses
  Folder/Folder.jpp when present; `using Folder.*` gathers siblings excluding that
  facade. Otherwise folders aggregate automatically. Mutual imports form one
  public dispatch unit; private visibility remains file-local.
- `export word` without local methods re-exports public imported implementations,
  or declares a required word when none exist. It supplies no dummy candidate.
  Check lexical calls/gates even in unused bodies; caller context cannot repair
  a missing declaration. Preserve raw LOCAL methods and original homes through
  re-export cycles. Typed universal contracts remain unbuilt.
- Tuple/record construction and required named calls share one pack model.
  Preserve source evaluation order; match positionals by index and names by name,
  without cross-fill. Compare named specificity by name, not declaration index.
  Explicit static fields retain values; incidental source literals stay data.
  Each section allows one trailing rest. Splats require statically shaped packs
  and never cross sections or overwrite fields. Fixed coverage outranks rest;
  compare rest element constraints pointwise, then use structural shape only
  for otherwise tied coordinates. Uniform T needs a witness when empty;
  short predicate rest annotations check each element independently.
  `design/` is a design notebook, not runnable regression fixtures.
- Split direct runtime enum inputs only when applicability or a body's
  type-valued result needs their case. Generic forwarding retains runtime enums;
  independent enum inputs must not automatically form a Cartesian table. Preserve
  composed type selection, such as the DWARF reader's intermediate offset type.
  Resolve each needed arm with the normal caller-first context and specificity
  rules; evaluate producers once. A selected enum becomes a static field within
  that branch. Non-exhaustive enums may travel through generic code, but requested
  enumeration still rejects them. Interacting inputs can still need combinations;
  opaque calls and pack results can conservatively retain extra dependencies.
  This is not a claim of optimal table construction. Tagged-union/error-set/error-union
  inputs retain eager refinement in this increment; union inputs become
  Variant(owner, tag) values with .payload. Keep owner/tag identity, static known
  arm coverage, runtime exhaustiveness, and return joins into the owning union.
  Variant groups are ordinary predicates. Do not introduce JSON-specific compiler
  rules, implicit catch-alls, or automatically split fields hidden inside records.
- Value qualifiers in `where` are ordinary boolean expressions over one fixed
  input per condition. Evaluate them at comptime from known values or type/tag
  facts; never fabricate runtime payloads. Require bool, keep
  guards' lexical dependencies and declaration homes through context collapse,
  and cache applicability by context/expression/input facts. Guards refine their
  base signature coordinate; exact cases remain above typed guarded defaults.
  Compare conjunctions and direct authored predicate order pointwise. Unknown
  implication stays incomparable. Runtime scalar guards and correlated/whole-rest
  conditions remain unbuilt. Native predicates must receive known inputs.
  Validate member paths rooted in known module values even in unused guards and
  ordinary bodies, without executing calls or inspecting unknown parameters.
- Native error values keep their shared name identity across error sets. Validate
  qualified members against their declared finite set. Exact errors refine native
  set annotations, and narrower sets refine supersets. `E!T` input branches expose
  success T or a known native error. Compatible branch results rejoin native error
  unions/sets, including tagged-union payload joins; producers still execute once.
  Runtime anyerror is open and rejected for table injection. Dispatch never adds
  implicit error propagation/early return. Tagged unions represent payload sums;
  first-class Sum constructors and callable predicate factories remain unbuilt.
- The enum interface is to be a tight Zig wrapper authored in the jpp library:
  preserve native type identity, cases, tag values and layout. Shared enum/union
  dispatch does not require a new common value representation. The wrapper API
  and primitive set remain OPEN. Try generic native primitives beneath jpp-only
  wrapper bodies, deriving them from composed source examples. Base.Zig exposes
  native namespaces through generic static member access. Table injection still
  lives in the core; native calls still require grounds.
- Module constants and exact enum member-path patterns are lexical comptime
  values. Preserve native identity through aliases, facades and re-export cycles.
  Initializers admit names, member paths, scalar literals and explicit grounds;
  ordinary calls await a staging contract. Aggregate constants may coalesce only
  when identical; different values or value/method collisions must error. Private
  constants stay file-local. These bindings do not implement overridable `=`.
- The JSON case adapts Zig std types as a foreign test fixture. It does not choose
  jpp's array representation, collection/iteration model, allocation or ownership.
  Keep those language decisions open; the objective is dispatch replacing switches.
- Local `name = expression` bindings are immutable aliases of ANF values.
  Preserve evaluation once and in source order, type identity, and the
  method-wide sequential binding environment. Rebinding and forward uses
  are frontend errors; mutable assignment and callable locals are unbuilt.
- `src/ast.zig` describes the intended AST but is not yet consumed by
  jppc. `spike/jpp.zig` retains the historical encoding needed by the
  tail-call probe; it is not the active runtime. The obsolete emitter and
  hand-transpiled demos live in git history. See `RUNNING.md` for the probes.
- Regenerate `gen/` and `tests/.gen/` through the build. Edit their source
  inputs rather than generated files; do not commit build artifacts.

## Validation

For compiler or semantics changes, run `zig build test`. It includes inline
machinery tests and every language case. Run `zig build demo` when changing
the default transpilation or execution path. Run `zig build probes` when
changing a mechanism covered by those probes.

Each language case is a folder under `tests/`, with a `test.md` explaining
the promise. Root modules defining `main` are separate programs with fresh
contexts. Use `using Base.Test` (or `using Base`) and `check` for assertions.
A case with `expect.err` must fail compilation with the specified diagnostic substring;
making it compile is a regression. Add meaningful coverage for changed
behavior and update the promise catalog when needed. Documentation-only
changes need a consistency review, not a repeated full test run.
Frontend rejection cases use `expect.transpile.err` instead: jppc must fail
with the specified substring, and no Zig compilation is attempted.

## Working style

Complete the requested work within its scope, using reasonable assumptions
for routine choices. Ask when an answer would change semantics or scope.
Keep explanations concise and distinguish verified results from inference.
Inspect existing edits before changing files and preserve work outside the
task. Run the relevant checks once after the final change; repeat only for
new changes, failures, or unresolved concerns. Report what changed, the
checks performed, and any remaining limitations.

Use commit history as project memory. Commit completed, coherent increments;
prefer short, memorable subjects that capture the concrete idea, such as
"Methods become switches". Keep messages concise; add a brief body only when a
decision or limitation is needed to understand the change later.
