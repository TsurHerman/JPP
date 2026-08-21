# Running jpp

Prerequisite: **Zig 0.16** (`brew install zig` / zig.dev). Zig is the
only dependency — it hosts the transpiler, executes the language's
semantics at comptime, and compiles the artifacts.

## The pipeline

```
demo/*.jpp --(jppc: parse -> ANF -> print)--> gen/*.zig --(zig + src/jpp.zig at comptime)--> native
```

Everything through `zig build`:

| command | what it does |
|---|---|
| `zig build transpile` | run the transpiler: `demo/*.jpp` -> `gen/*.zig` |
| `zig build demo` | transpile, compile `gen/run.zig`, run the demo program |
| `zig build test` | machinery tests (`src/jpp.zig`, 12) + boundary tests (`tests/`, 3) |
| `zig build probes` | the validated spike probes (interp, enum, binder, vec) |

Raw equivalents (no build system): `zig run src/jppc.zig`, then
`zig run gen/run.zig`; `zig test src/jpp.zig`; `zig test spike/<probe>.zig`.

The demo's expected output: three contexts, one source tree, three
programs — plain (`main`), print-overridden (`loud_main`), and a
grandparent `+`-override reaching through two oblivious modules
(`tweaked_main`: 43 / 87 / 1849 — `*` stays honest).

## Layout

| path | what it is |
|---|---|
| `README.md` | THE language definition: every ratified decision, with rationale |
| `RUNNING.md` | this file |
| `build.zig` | orchestrator (ratified: zig build drives jpp) |
| `src/jpp.zig` | the machinery: methods-as-data interpreters, dispatch, `<:` order, collapse — executes at COMPTIME inside generated code; 12 tests inline |
| `src/jppc.zig` | the transpiler: lexer -> parser -> ANF -> data-literal printer -> driver; deliberately dumb (file-local, context-blind) |
| `src/ast.zig` | the ratified three-layer AST model (Expr/Method/FlatBody); jppc does not consume it yet — acknowledged debt |
| `src/emit.zig` | v1 emitter, superseded by the five-facts data shape; history |
| `demo/*.jpp` | the first runnable jpp programs (ints, floats, io, algebra, loud, stats, tweaked, three mains) |
| `design/*.jpp` | design-phase sketches of the future corpus (reals, promote rules, intrinsics, tensors) — use surface features ahead of the v1 parser; not yet transpilable |
| `tests/` | language-promise boundary tests + the promise catalog (`tests/README.md`) |
| `spike/` | validated probes, each a self-contained proof of one mechanism (see below) |
| `gen/` | derived output — gitignored, regenerate anytime |

## Probe inventory (spike/)

| probe | proves |
|---|---|
| `interpprobe.zig` | methods as pure data: signature + body interpreters, policy word, delegation, collapse (11 tests) |
| `enumprobe.zig` | value dispatch + runtime enum bridge (`inline else`), nesting, int ranges (5) |
| `binderprobe.zig` | two-section packs, no cross-fill, permuted named args -> one instance (4) |
| `vecprobe.zig` | parametric type-words: pattern binding, unification, re-application provenance (5) |
| `soprobe.zig` | dlopen/dlsym symbol probing — the symbol-name-as-cache-key venue |
| `tailcalls.zig` + `tailprobe*.zig` | guaranteed tail calls through the encoding; documents the comptime mutual-recursion landmine (§11) — slow to compile by design of the experiment |
| `jpp.zig` + `ints/floats/reals/checked/lib/main.zig` | the ORIGINAL hand-transpiled spike (pre data-shape); superseded by src/jpp.zig but kept as the historical reference implementation |
| `emit.zig` -> `gen_double.zig`/`gen_main.zig` | v1 emitter round-trip; historical |
