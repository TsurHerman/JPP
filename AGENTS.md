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
  and print Zig data literals. Keep it file-local and context-blind.
- `src/jpp.zig` owns dispatch, binding, context accumulation, specificity,
  and the order word. These execute at Zig comptime in generated code.
- Preserve caller-first accumulated context, pointwise dominance rather
  than summed ranks, context-position tie-breaking across modules, and
  ambiguity errors at calls with competing maxima in the winning module.
- A defined/imported name in a signature refers to its existing value; a
  fresh name binds an input. Never manufacture class identities from
  undefined names. Annotated inputs may be unused: their annotation gives
  them a signature role. Only unused, unannotated fresh names error;
  anonymous inputs remain an option. Type values retain their identity in
  comptime pack fields; an integer value and its type are different call
  arguments.
- Private helpers are lexical; exported words fuse through caller context.
  Preserve a method's declaration home when aggregating folders.
- The `<:` order is authored and queried pairwise between candidates.
  There is no implicit transitive closure. A negative test demonstrating
  a missing edge is a language promise, not a resolver bug.
  Mutual pairs do not imply a transitive equivalence relation. Keep losing
  candidates needed for other dominance decisions during context collapse.
- `Base/` supplies library modules; the source tree can shadow their names.
  `design/` contains future syntax, not runnable regression fixtures.
- `src/ast.zig` describes the intended AST but is not yet consumed by
  jppc. `src/emit.zig` and the original hand-transpiled spike are historical.
  Use `RUNNING.md` to distinguish these from the validated probes.
- Regenerate `gen/` and `tests/.gen/` through the build. Edit their source
  inputs rather than generated files; do not commit build artifacts.

## Validation

For compiler or semantics changes, run `zig build test`. It includes inline
machinery tests and every language case. Run `zig build demo` when changing
the default transpilation or execution path. Run `zig build probes` when
changing a mechanism covered by those probes.

Each language case is a folder under `tests/`, with a `test.md` explaining
the promise. Root modules defining `main` are separate programs with fresh
contexts. Use `using Test` and `check` for assertions. A case with
`expect.err` must fail compilation with the specified diagnostic substring;
making it compile is a regression. Add meaningful coverage for changed
behavior and update the promise catalog when needed. Documentation-only
changes need a consistency review, not a repeated full test run.

## Working style

Complete the requested work within its scope, using reasonable assumptions
for routine choices. Ask when an answer would change semantics or scope.
Keep explanations concise and distinguish verified results from inference.
Inspect existing edits before changing files and preserve work outside the
task. Run the relevant checks once after the final change; repeat only for
new changes, failures, or unresolved concerns. Report what changed, the
checks performed, and any remaining limitations.
