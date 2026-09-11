# Running jpp

Prerequisite: **Zig 0.16** (`brew install zig` / zig.dev). Zig is the
only dependency — it hosts the transpiler, executes the language's
semantics at comptime, and compiles the artifacts.

## The pipeline

```
tests/*.jpp --(jppc: parse -> ANF -> print)--> gen/*.zig --(zig + src/jpp.zig at comptime)--> native
```

Everything through `zig build`:

| command | what it does |
|---|---|
| `zig build transpile` | transpile the default case (`tests/dispatch`) -> `gen/` |
| `zig build demo` | transpile, compile, run the default case (ok-lines + verdict) |
| `zig build test` | inline machinery tests in src/jpp.zig + all language cases |
| `zig build lang-tests` | the language cases, each self-reporting `[case] PASS|FAIL` |
| `zig build probes` | the validated spike probes (interp, enum, binder, vec) |

Raw equivalents (no build system): `zig run src/jppc.zig -- [src_root]
[out_dir]` (discovers `.jpp` recursively; a program is a root module
that defines `main`; `Base/` modules join every tree, the tree's own
shadow them), then `zig run <out_dir>/run.zig`.
`zig test src/jpp.zig`; `zig test spike/<probe>.zig`.

For a larger runnable example, read [the checkout case study](tests/checkout/test.md):

```sh
zig run src/jppc.zig -- tests/checkout tests/.gen/checkout
zig run tests/.gen/checkout/run.zig
```

It prices baskets through nested modules in two application contexts,
prints receipts, and checks the totals. It also runs under `zig build test`.

**The case contract (unix, self-judging, ONE artifact):** jppc emits a
single `run.zig` per tree. Each program (root module defining `main`)
runs as a fresh root context; `check(name, got, want)` (from
`Base/Test.jpp`) prints `ok <name>` or `FAIL <name>: got X want Y` and
records failures; contrast cases print `[case/world] PASS|FAIL` then
`[case] PASS — N programs`. Exit **0 / 1**. No separate judge, no
output oracle — the program judges itself; CI and `zig build` trust
the exit code. `zig build lang-tests` walks `tests/` for case folders.
NEGATIVE cases: `expect.err` in the folder flips the contract — the
harness compiles the case expecting FAILURE and greps the error for
the file's text (error promises: ambiguity, declaration binding, type-only order, export gating).

## Layout

| path | what it is |
|---|---|
| `README.md` | THE language definition: every ratified decision, with rationale |
| `RUNNING.md` | this file |
| `build.zig` | orchestrator (ratified: zig build drives jpp) |
| `src/jpp.zig` | the machinery: methods-as-data interpreters, dispatch, `<:` order, collapse — executes at COMPTIME inside generated code; machinery tests live inline |
| `src/jppc.zig` | the transpiler: lexer -> parser -> ANF -> data-literal printer -> aggregates -> driver; deliberately dumb (file-local, context-blind) |
| `src/ast.zig` | the ratified three-layer AST model (Expr/Method/FlatBody); jppc does not consume it yet — acknowledged debt |
| `src/emit.zig` | v1 emitter, superseded by the five-facts data shape; history |
| `tests/` | the language cases: each folder a tree; programs are root modules that define `main` (see `tests/README.md`) |
| `Base/` | the jpp library — `Test.jpp` first; `using Test` works from any tree, tree modules shadow Base. Zig's `std` is only inside `zig{}` |
| `design/*.jpp` | design-phase sketches of the future corpus (reals, promote rules, intrinsics, tensors) — use surface features ahead of the v1 parser; not yet transpilable |
| `tests/README.md` | the promise catalog and suite conventions (machinery tests live inline in `src/jpp.zig`) |
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

## Developing with GPT-6 Astra

`AGENTS.md` describes the architecture, language promises, and validation
rules for coding agents. `.codex/config.toml` selects the repository's
Codex model and preserves the existing development reasoning setting:

```toml
model = "gpt-6-astra"
model_reasoning_effort = "xhigh"
```

Codex CLI and IDE load project configuration for trusted repositories.
Explicit launch overrides can take precedence. Check the active model in
the Codex client when starting work; a project default does not establish
the model of an already-running task. See the official OpenAI documentation
for [configuration](https://learn.chatgpt.com/docs/config-file/config-basic)
and [Astra migration guidance](https://developers.openai.com/api/docs/guides/latest-model).

For future model comparisons, use the same starting tree and task prompts:
explain `context_flip`, diagnose the intentional `lattice_gap` failure
against `lattice_bridge`, and make a bounded compiler change with a language
regression case. Compare correctness, adherence to the design, unnecessary
edits, elapsed time, and usage. Require no new suite failures and preserve
the negative-case diagnostics. Change effort or instructions in response to
observed problems. To roll back model selection, set the previous supported
model and effort explicitly; removing this file restores inherited defaults.
