# jpp — language definition (working draft)

Julia-class scientific computing, taken seriously about compilation.
Dynamic feel while developing; everything is native code all the time;
sealed builds are small static binaries. Reference document:
[Julep: Taking multiple dispatch, export, import, binary compilation seriously](https://discourse.julialang.org/t/julep-taking-multiple-dispatch-export-import-binary-compilation-seriously/10882) (2018).

Guiding principle — **julia-9/10**: when a question is about numerics or
surface culture, Julia's answer is jpp's answer. Deviations are explicit
and registered (see bottom).

**To run anything** (demo, tests, probes): see `RUNNING.md` — one
dependency (zig 0.16), four `zig build` steps. The language-promise
test catalog lives in `tests/README.md`.

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
- **Exports gate everything (ratified).** A word callable from outside
  its module — by fusion (`using`) OR by qualification (`M.f`) — must
  be labeled `export`. One closed interface per module; internals
  exist only inside the module's own context. Simplification bought:
  export maps 1:1 to Zig's `pub` (exported words emit `pub const
  @"f"`, internals drop the `pub`), so the SUBSTRATE enforces
  visibility — the resolver's `@hasDecl` walk already respects it,
  private helpers can never join anyone's fusion or cross with
  anyone's words, and sealing gets a closed per-module root set for
  dead-code elimination.
- **Ordered context (ratified, supersedes the hard extension-only
  rule).** A context is an ordered list `[caller's chain..., imports in
  order...]`. Resolution: specificity first; on rank ties, earlier
  position wins. Same-territory re-coverage is legal *shadowing* —
  newer code can override old behavior deterministically. Piracy stays
  impossible for the original reason: an override only affects
  resolutions in contexts that include it. Within-module same-rank
  ambiguity is a transpile-time error.
- **Context reaches downward, and accumulates.** Entering a resolved
  method, the effective context becomes `caller_ctx ++ callee's static
  context` (deduped, caller stays ahead) — so the caller's overrides
  outrank even the callee's own imports. Generic code (`sum` calling
  `+`) sees the caller's extensions. Context is a compile-time
  specialization parameter, monomorphized away — never a runtime value.
- **Compiled instances are keyed by `(function, argument types, context
  methods actually reached)`.** All keys static. Editing a module
  invalidates exactly the instances that reached it — invalidation flows
  toward callers, never into the base libraries. (The invalidation model
  is the push/pull signal graph of Signals.jl, applied to compilation.)

## 2. Types, values, comptime

- Types are ordinary compile-time values. Functions on types are
  ordinary functions that run at compile time.
- Top level runs at compile time; there is no "load time".
- `for` at top level runs at comptime and can *generate methods* —
  this is jpp's `eval`: staged codegen, closed by the build.
- Functions are comptime values (`for op in (+, -, *) { ... }`).
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
  returns a type; every type has its `()`. Value patterns (exact values,
  ranges) live ONLY here. Any comptime value binds; a RUNTIME selector
  is legal iff its domain is closed (enum, bool, bounded int) — the
  bridge lifts it per slot into the collected switch. Open domains
  (types, comptime_int, floats, strings) are comptime-only selectors.
- **Parens — data**: dispatched on TYPES only, never values, never
  bridged. Positional tuple, then `;`, then named record. No
  cross-fill; named args permute freely; declared order is canonical.
- **Return** optional; absent = inferred (body mirrored in context).
- **`where` — the last gate**: ONE comptime predicate over everything
  the signature bound (selectors, implicit type vars, named-slot
  types). Runs last in the binder; failure is a quiet no-match. Sugar
  identity: `B<:Integer` ≡ `B` + `where Integer(B)`, same rank.
- **Body**: expression block (value = last expression) or ground axiom
  (`zig{}`, `c{}`, `llvm{}` — no context dispatch inside).
- **Specificity per slot**: exact 3, predicate 2, bare 1, variadic 0;
  pointwise dominance decides (§9 policy word); incomparable-or-equal
  maxima break by context position across modules, and are a comptime
  ambiguity error AT THE CALL when they share the winning module
  (julia's venue — define the intersection method).
- **Underneath**: the signature is a pack CONSTRUCTOR; calling is
  constructing the parameter struct (the binder); the bound pack is
  the instance identity and the `.so` symbol key.

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
`A == Vector{A.Elem, A.len}` — memoized type identity makes
application injective, so forged stamps cannot pass. All validated:
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
per-slot lexicographic rank (summed for now); `struct` declaration
sugar for parametric type-words.

Argument position:

| form         | meaning                                            |
|--------------|----------------------------------------------------|
| `x::int32`   | exact type. `::` annotates what the argument IS — no puns |
| `T::type`    | the argument is a type value (kind annotation)     |
| `x<:Integer` | guard on the TYPE of x — `Integer(typeof(x))`      |
| `::arm64`    | anonymous exact comptime VALUE match               |
| `where P(A)` | predicates on comptime values go in `where`        |

Brace position — extra comptime parameters, **only** those not inferable
from the value arguments; supplied at call site as `f{T}(x)`:

| form               | meaning                                       |
|--------------------|-----------------------------------------------|
| `f{T}(x)`          | bind any comptime value (generic)             |
| `f{T<:Integer}(x)` | bind + predicate; sugar for `f{T}(x) where Integer(T)` |
| `f{Integer}(x)`    | anonymous predicate slot (name unneeded)      |
| `f{int32}(x)`      | EXACT comptime value — most specific          |

Variadic and tuples (ratified):

- `f{TT...}` / `f(args...)` in definition position: remaining slots bind
  as ONE tuple. Call-side splat `t...` is the inverse.
- Tuple utilities (`len{TT}`, `first{TT}`, `beheaded{TT}`) take the
  tuple as a single slot; only genuinely variadic functions (`promote`)
  bind with `{TT...}`. Bridging the two is always an explicit splat:
  `promote{beheaded{TT}...}`.
- `()` is the empty tuple; it splats to zero arguments. `beheaded` of a
  1-tuple is `()`, not `nothing`.
- Variadic recursion discipline: a variadic method must not cover the
  arity owned by specific rules (see core's `promote{TT...}`: cases
  `len == 1` and `len >= 3` only — binary rules own 2, and a missing
  binary rule errors at the call site naming both types).

- Specificity ladder, both positions: **exact > predicate > bare >
  variadic**.
- **Methods are unary (ratified).** A method takes ONE argument: a
  struct (the pack). `f(a, b)` constructs the anonymous pack `(a, b)`
  and applies f to it; the parameter list is a PATTERN over the pack's
  fields; dispatch is structural dispatch on the pack's single type
  (instance key: method × context × pack type). A variadic method
  matches ANY pack — destructuring is the extractor vocabulary (`len`,
  `first`, `beheaded`, field access), ordinary comptime library code.
  Splat is a cast, not a computation: `f(t)` wraps t as a one-field
  pack, `f(t...)` uses t AS the pack. Consequences: named fields are
  keyword arguments that PARTICIPATE IN DISPATCH (julia's kwargs
  don't); uniform `fn(ctx, pack)` signatures ease musttail. Named-field
  specificity rules: parked until kwargs land. This ratifies what the
  emission already did — `jpp.call(ctx, "f", .{a, b})` was always
  unary.
- **The pack is two sections; the binder is the semantic layer
  (ratified, validated: `spike/binderprobe.zig`).** A pack is an
  ordered TUPLE (positional) followed by a RECORD (named). The
  convention holds at call sites and in definitions: positional slots
  are a prefix, `;` opens the named section (julia's kwarg separator —
  julia-9/10). Binding never crosses sections — positional slots fill
  by index only, named slots by name only — so the dispatch footgun
  (methods differing only in slot order colliding through named calls)
  is grammatically impossible. Named args permute freely among
  THEMSELVES (a record is a set); the method's declared order is the
  canonical form. The call-site protocol: (1) the transpiler emits the
  RAW pack exactly as written — positionals as numeric field names
  `.@"0"`, `.@"1"`, named verbatim (zig literals reject duplicate
  names, so double-fill is unwritable); (2) each candidate method's
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
- **Value dispatch and the runtime enum bridge (validated:
  `spike/enumprobe.zig`).** Dispatch on exact enum VALUES needs no new
  mechanism: Zig's anonymous packs make comptime-known initializers
  comptime FIELDS, so `@TypeOf(.{Mode.fast})` carries the value and the
  existing exact-beats-bare ladder covers `F{Mode.fast}` vs `F{mode}`
  (value dispatch lives in the SELECTOR section — see the complete
  shape above; data slots dispatch on types only and never bridge).
  The new piece is the BRIDGE for runtime values: the
  ground machinery lifts a runtime enum field to comptime with
  `switch (x) { inline else => |v| ... }` — one arm per variant, each
  re-entering ordinary comptime dispatch with the value known. The
  collected arms ARE the switch table; semantics stays single (dispatch
  is always on fully comptime-known shape) and tier-invariant. This is
  julia's union-splitting promoted from optimizer heuristic to language
  semantics. Consequences: exhaustiveness for free (no default method +
  an uncovered variant = comptime error naming it, even for runtime
  values); tables are per-instantiation (word × context × pack type) —
  a context adding `F{Mode.fast}` changes the compiled switch, sealing
  freezes it. Expansion policy (ratified): JUST NEST IT — no probing
  heuristic, no optimizer-dependent meaning. The bridge lifts ONE
  runtime field per re-entry, left to right; a pack with several
  runtime enums nests automatically (validated). The cartesian product
  is the user's own specialization budget: if they wrote explosive
  numbers of specializations, they are supported; identical arms fold
  downstream. Integers can't inline-else (2^64 arms) — they bridge
  through DECLARED range patterns as Zig range arms
  (`inline 0...9 => |v|` lifts each value in range to comptime;
  validated), with the else arm going to the unconstrained methods.
  The purpose: PROMOTE BRANCHING OUT OF THE LANGUAGE — if/else/switch
  are not surface control flow the user schedules but a semantic step
  the compiler completes: you write specialized methods, dispatch
  collects the branch. The ternary select remains the value-selection
  primitive. Note: the spike's `matches([]const type)` interface CANNOT
  see comptime field values — the pack-type interface rework is
  mandatory, not cosmetic. Natural extension, unprobed: tagged unions —
  switch on the tag, dispatch per payload type; jpp's
  sum-type/pattern-matching story.
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
over reflection guards where the rule table is total (see `reals.jpp`
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
- **The unit of computation is the call** (reference: Thorin/AnyDSL,
  "A Graph-Based Higher-Order IR", CGO'15). A binding is not
  computation — it names a data edge, and is erased at emission (jpp
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
  boundary (ratified — zig infers a ground block's type via a @TypeOf
  mirror of the body over an undefined pack: analyzed, never executed).
  Same rule as jpp-level bodies — one inference story everywhere.
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
  generated methods in `reals.jpp`. A context that doesn't import them
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
  least one, computed on per-pack PROJECTIONS (exact 3, predicate 2 —
  including ranges and single-binder where-conjuncts, bare 1,
  variadic-covered 0; tuple by position, record by name, selectors as
  ordinary slots). Sum and lexicographic were considered and rejected
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
- **The order is a word: `<:` (ratified, validated).** Implication
  between predicates is AUTHORED, never proven — jpp builds no prover.
  Modules declare edges on the word `<:` (`Integer <: Real`),
  context-resolved like everything else: the entitlement principle
  extends to the order itself. Four ways to tell "all of a satisfies
  b", and semantics only ever needs the first: (1) point witness —
  at a call the pack is in hand, `exact<=pred` is just Q(T), so
  dispatch NEVER hits the undecidable cells; (2) authored edge —
  julia's abstract tree IS this: `Int <: Integer <: Real` is
  declaration, not derivation; (3) counterexample over the known
  universe (ledger refutation); (4) unknown — which only ever widens
  a lint. Consequences: within the predicate rank, dominance refines
  through the declared edges — `f(x<:Integer)` beats `f(x<:Real)`
  where the edge exists (validated: same-module narrow/wide pair,
  ambiguity error without the edge, clean dominance with it);
  deciding `<:(F1,F2)` dispatches on function IDENTITY, never on
  implication — no circularity (judge-by-seniority again);
  reflexivity free, transitivity NOT automatic (declared pairs only;
  comptime closure a future nicety); the static-order functions
  (`sigLeq`, `ambiguousPair`, `resolves`, `sigMeet` — the ledger's
  primitives, three-valued, julia's intersection fix constructible
  and printable) consult the same edges. THE JUDGE TRAVELS, AND SO
  DOES THE ORDER: `specificity` and `<:` declarations always survive
  context collapse — they shape decisions without being footprint
  words. V1 encoding: edge data under decl `@"<:"` (jpp.Edges);
  dissolves into ordinary methods on the word when value-exact quals
  land in construct (§4 rework). STRATIFICATION (ratified, implemented):
  resolution internally resolves `<:`, so `<:` must be special to
  avoid recursion — the machinery's own words (`<:`, `specificity`)
  resolve at STRATUM 0: rank-only bare ladder, no edge refinement, no
  policy word. Sufficient forever: `<:`'s own methods dispatch on
  function IDENTITY (exact values) and never need pred-vs-pred
  comparison. This is the recursion-break pattern's third instance,
  now named as THE principle: every self-referential piece of the
  machinery bottoms out in a stratum-0 version of itself that does not
  self-refer (matcher is ground; judge by seniority; order by bare
  ladder). User-predicate cycles are the separate §3 backstop
  (in-progress set -> quiet no-match). GRAMMAR (ratified, ironed,
  validated): a `<:` declaration is a FACT or a GATED RULE — nothing
  pattern-shaped:
  - FACT: `<:(::literal, ::literal) = true|false` where a literal is
    a type or a name. SEMANTICS (ratified): a universally quantified
    AUTHORED assertion between classes — any type answering the first
    is below any type answering the second. Covers both INCLUSION
    pairs (`Integer <: Real`, overlapping) and TOWER pairs
    (`Int <: Float`, disjoint — "ints sit below floats"): one
    relation, consumers pick relevance — specificity refinement only
    consults overlapping candidates (below = narrower), promote and
    user code read the tower. Negative facts (`= false`) are how a
    context shadows an edge OFF. name×name = order fact; type×name =
    MEMBERSHIP fact (julia's `primitive type Int64 <: Signed` is
    exactly this; transpiler may fuse with predicate methods).
  - GATED RULE: `<:(P, Q) where gate = expr` — where sits BEFORE `=`,
    the gate is part of the constructor (canonical placement, one
    spelling). Bare binders + where, NEVER predicate-qualed slots
    (that would consult the order about the order). Decidable because predLeq queries arrive with BOTH
    arguments concrete: the gate is point-evaluated at the query's
    witnesses, memoized per pair — never quantified over, no prover.
    Tri-valued: true/false are ANSWERS, "not my domain" passes.
    Gates receive only (P, Q) — no ctx BY SIGNATURE: a rule
    physically cannot recurse into resolution.
  - LOOKUP (first answer wins): identity is an UNSHADOWABLE axiom
    (self-facts are dead letters); then module by module in context
    order, facts before rules within each module; the first ANSWER —
    true or false — stops the search; miss everywhere = false (the
    no-prover floor, a machinery axiom, unwritable as a method).
  - IRONED CASES (all validated, src/jpp.zig): negative facts flip by
    position; a module's fact beats its own rule; NO transitive
    closure (chains are authored or absent; explicit derivation over
    edge data if ever wanted). CYCLES MEAN IDENTITY (ratified): mutual
    edges declare EQUIVALENCE — the members collapse into one class,
    THE CYCLE IS THE TYPE (the preorder quotients; condensation). The
    machinery's behavior is already correct: equal specificity is
    exactly right for identical classes — same-module methods on one
    class genuinely collide (ambiguity error), cross-module resolves
    by position. A declaration form, not a smell: the ledger reports
    "equivalence declared", never "cycle detected". Structure lives in
    predicate BODIES (point-evaluated, always decidable); order lives
    in facts and gated rules; the undecidable middle has no syntax.
  LITERAL-HEAVY WORDS COMPILE TO TABLES (ratified): `<:` will carry
  MANY literal declarations (numeric tower, user domains, comptime-for
  generated families). A population of bodiless exact-value facts is
  semantically a lookup TABLE — mutually disjoint by identity, trivial
  dominance, constant bodies — so the compiled form is an ordered
  per-module table, unioned through the context, first hit wins
  (implements shadowing/position exactly). The v1 `Edges` encoding IS
  this table; when `<:`-as-methods lands, the transpiler detects
  all-exact-fact populations and emits them back down to tables:
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
  - Historical (validated by `spike/` + generated code, now
    superseded): v1 emitted per-method structs with
    `rank/matches/Ret/call` functions. The spike proved the lowering;
    the five-facts data shape is the ratified direction, spike rework
    pending.

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
  drop (decl-level). V2, DECISION-level (ratified + validated): all
  defs are comptime, so the decision profile is computable BEFORE
  instantiation — the same walk that infers types discovers every
  inner pack, and recording which module WON each resolution is a free
  byproduct. Soundness theorem: REMOVING A LOSER NEVER CHANGES THE
  WINNERS (dominance is pairwise among candidates; position order
  survives subsequence) — so modules that declare footprint words but
  never win drop with no re-verification (validated: a u8-only `+`
  declarer collapses away from an i64 instance; an i64 `+` that wins
  survives). The selected judge counts as a winner; shadowed judges
  never judged and drop. Recursive bodies need the in-progress set
  (the known landmine venue). Wired into `call` itself, so every
  dispatch collapses automatically; the whole probe suite passes
  unchanged = semantics preserved.
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
  7/7 dispatch-semantics tests.
- `src/jppc.zig` — the transpiler: lexer (ground capture with
  string-skipping), parser (defs, params, infix precedence, blocks),
  normalizer (ANF), emitter (five-fact data literals + ground fn
  structs with @TypeOf-mirror inferred returns), driver
  (demo/ -> gen/, machinery copied alongside, harness generated).
- `demo/*.jpp` — ints, floats, io (dispatched print), algebra
  (generic double/square/describe — imports ONLY io: it computes with
  `+`/`*` it never imports, the callers' chains supply the arithmetic
  as context flows downward; validated), loud (caller override), two
  mains. A module's implicit needs (words its bodies use beyond its
  usings) are computable from the footprint closure — the ledger can
  print "algebra requires from context: +, *" — an implicit contract
  made checkable. DEPTH (validated): a caller of a caller of a caller
  overrides surgically — `tweaked_main -> stats -> algebra -> +` with
  an off-by-one `+` declared at the top passes through two oblivious
  modules (double(21)=43, double(43)=87) while `*` stays stock
  (square(43)=1849): per-word, per-signature, unlimited depth, zero
  cooperation below, and pay-per-use instances via collapse.
- Validated behaviors, from TEXT: multiple dispatch on print
  (int64/float64), generic methods flowing through ground arithmetic
  per element type, blocks/sequencing, literals as typed data, return
  inference through jpp bodies AND across the ground boundary, and the
  founding sentence: `loud_main.jpp` leads its context with `loud` and
  gets `INT!!!` from inside `describe`/`double`/`square` — modules
  that never imported it.
- V1 scope cuts (deliberate): no selectors/braces in the surface, no
  predicates in the surface (machinery supports both), no promotion,
  no named-arg syntax, module list hardcoded in the driver, reduced
  internal AST (alignment with src/ast.zig's three layers = debt),
  no spans/hashes emitted yet.

## 11. Open

- **Next phase (declared):** first, the boundary-testing phase — write
  the promise catalog (`tests/README.md`) into executable claims,
  including the negative-compile harness for error promises. Once that
  phase completes, decide: THREADING model, and the STANDARD LIBRARY
  strategy — stay on zig std (grounds call it directly, as `io.jpp`
  does today), wrap it in jpp words per domain, or rewrite selected
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
