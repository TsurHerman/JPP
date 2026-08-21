# tests/ — the language's promises, as executable claims

The probes in `spike/` validated *mechanisms* in isolation while the
design settled. This suite pins the *promises* — the guarantees the
README ratifies — against the real machinery (`src/jpp.zig`), which is
what the transpiler emits against. Run with `zig build test`.

## Promise catalog and coverage

| # | Promise (README ref) | Covered today | Boundary tests to write |
|---|---|---|---|
| 1 | Specificity ladder: exact > pred > bare; dominance, never sum (§4, §9) | machinery tests (bar lattice, ladder) | per-slot projections with variadics; named-record alignment |
| 2 | Ambiguity: same-module crossing = comptime error at the call; intersection method cures (§9) | machinery tests + negative check (by hand) | scripted negative-compile harness (`zig build` expecting failure) |
| 3 | Ordered context: position breaks ties/crossings; flip flips (§1, §9) | machinery tests | deeper chains; interleaved shadowing |
| 4 | Context accumulation: caller ahead, callee STATIC behind, dedup (§1) | demo (implicit) | direct machinery test of extendAll ordering |
| 5 | Depth overrides: caller-of-caller, surgical per word (§1, §10.5) | demo (`tweaked_main`) | machinery test; override at 4+ levels; two overrides at different depths |
| 6 | Delegation: `M.f` selects in M, body propagates caller (§1) | **tests/boundaries.zig** | delegation into a chain; delegated word absent in M = error |
| 7 | Collapse: resolving module owns instance; pay-per-use shadowing (§9) | **tests/boundaries.zig** | v2 winner-collapse on real machinery; symbol-hash stability once hashes land |
| 8 | Exports gate everything: pub IS the gate (§1) | **tests/boundaries.zig** | qualified-access gating once `M.f` surface lands |
| 9 | The order `<:`: facts, gated rules, negative facts, first-answer, cycles=identity, no closure (§9) | machinery tests (7 ironing cases) | order-shadowing THROUGH call chains; ledger output |
| 10 | Binder: two-section packs, no cross-fill, named permutation converges (§4) | binderprobe (spike) | port to real machinery; named-arg dispatch end to end |
| 11 | Enum bridge: value selectors, nesting, ranges, exhaustiveness (§4) | enumprobe (spike) | port to real machinery once selectors land in `construct` |
| 12 | Parametric type-words: pattern binding, re-application provenance (§4) | vecprobe (spike) | port once value-exact quals land |
| 13 | Tier invariance: same observable behavior across tiers (§9) | — | needs the tier infrastructure first |
| 14 | Symbol-name-as-key: permuted call sites, one symbol (§9) | soprobe (dlsym only) | needs content hashes in the emitter |
| 15 | Transpiler round-trip: demo output byte-stable, semantics preserved | demo (manual) | golden-output test of `gen/` + demo stdout |

## Conventions

- One promise per test name, phrased as the promise ("collapse: an
  inert caller converges...").
- Negative-compile claims (ambiguity errors, gating errors) can't be
  passing `test` blocks — they get a scripted harness (a build step
  that EXPECTS compilation failure and greps the message). To build.
- Fixtures that need cross-file visibility (export gating) live in
  `tests/fixtures/`.
