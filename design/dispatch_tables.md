# Methods describe cases; specialization builds control flow

Status: automatic enum/tagged-union/error-set/error-union calls RUN in the active machinery. The
serialization and DWARF cases below are executable jpp, not proposed syntax.
Defined enum/error values and member paths now work in signatures (2026-09-20).
Boolean value qualifiers and explicit classifier comparisons run over known
branch facts, with ordinary typed defaults. General
static application and dedicated enum declarations remain unbuilt.

RATIFIED principle: a branch establishes a fact that ordinary dispatch can use
inside that branch; knowing the fact at comptime removes the runtime test.
The value itself may remain runtime data. General fact representation and
runtime-predicate rules below remain OPEN. The implemented qualifiers do not
support deciding a branch from unknown runtime numbers or payload contents.

## One resolver, refined inputs

Clarified with the user, 2026-09-20: enum tables inherit ordinary method
precedence. A function called with a direct runtime enum input implicitly
switches on that input. Inside each branch the selected case is known at
compile time, and the normal resolver chooses the implementation using that
refined argument pack and the same accumulated caller context.

Conceptually:

```text
call f(runtime_enum, other_arguments) in context C
    for each declared enum case K:
        runtime branch K:
            resolve f(static K, other_arguments) in context C
            execute the selected implementation
```

The compiler resolves those branches before execution. Runtime chooses a branch;
it does not search for methods. The case stays known within that specialized
path, including ordinary nested calls that forward it. Other arguments and union
payloads can remain runtime data. A case known before the call needs only its
own branch. Results merged after different runtime branches need not retain one
known case.

This applies to predicate functions too. A predicate used by `where` has the
same ordinary calls, context accumulation and enum specialization as any other
function. Its boolean result determines applicability; the shared resolver
determines preference among applicable methods.

Predictable resolution currently means pointwise dominance with pairwise authored
`<:` relationships, context position between surviving candidates in different
modules, and an ambiguity error for competing maxima in the winning module/unit.
This is a partial precedence relation, not a global sorted list. Applicability
can differ between enum cases. Any future ordered decision plan must preserve the
resolver's result in each case, including ambiguity and missing-coverage errors;
linearizing candidates must not introduce implicit transitive `<:` edges.

`src/jpp.zig` already implements this path through `bridgeRet`, `bridgeCall` and
the normal `resolve`. `enum_guard_order` demonstrates authored predicate order;
`log_labels` exercises a caller policy through nested predicate calls. Designing
an inspectable method-ordering plan is a separate task from the enum bridge.

## Ordered predicates and staging

Research and user clarification, 2026-09-20. This discussion concerns the
predicate evaluated by `where`, including decision tables within that predicate.
It does not change the precedence of context-dispatched methods. Within an
ordered decision, `if / else if / else` tests a row, continues when false, and
executes the first successful row's body. Overlap is allowed and order is
meaningful. This is fall-through between failed tests; one body executes.

The native languages distinguish two mechanisms:

- [Zig 0.16 switch](https://ziglang.org/documentation/0.16.0/#switch) requires
  compile-time case values and rejects overlapping values/ranges. It has no
  general runtime predicate guard on a prong. Local Zig 0.16 probes confirmed
  `0...10` overlapping `5...20` produces `duplicate switch value`, and a case
  `positive(x)` with runtime x produces `switch prong values must be comptime-known`.
  An ordinary ordered if/else chain with overlapping conditions compiles.
- [Rust match guards](https://doc.rust-lang.org/reference/expressions/match-expr.html#match-guards)
  permit boolean predicates and examine alternatives in order. A failed guard
  continues the search. The first successful pattern/guard selects the body.
  Arbitrary guarded arms do not establish coverage by themselves; the
  [Rust book](https://doc.rust-lang.org/book/ch19-03-pattern-syntax.html#adding-conditionals-with-match-guards)
  explains this limit.
- [Julia multiple dispatch](https://docs.julialang.org/en/v1/manual/methods/#Method-Ambiguities)
  instead selects by specificity and reports unresolved overlaps. This is closer
  to jpp's current method resolver than to an ordered predicate table.

An upload-buffer predicate illustrates intentional overlap within one boolean
calculation. Its Zig body makes the decision order explicit:

```jpp
mayBuffer(bytes::uint64, interactive::bool)::bool = zig{
    if (bytes >= 1_048_576) false
    else if (interactive) true
    else bytes <= 65_536
}
```

A large interactive upload satisfies both first and second conditions. The
first returns false, keeping large uploads out of memory. A smaller interactive
upload reaches the second condition and returns true. These are ordered branches
inside one predicate, not priority declarations between separate jpp methods.

The proposed extension lets a `where mayBuffer(bytes, interactive)` condition
specialize this calculation using known facts, retaining unresolved decisions at
runtime. The current compiler does not support that multi-input runtime guard.
If interactive is known true but bytes is unknown, the size check must remain;
knowing the second branch succeeds does not bypass the earlier condition. If both
inputs are known, the whole predicate can reduce to a boolean. Arguments are
produced once. A runtime branch establishes a fact without making the argument's
full value known.

Names retain their meaning across stages. `source::int64` binds an integer;
`sameAccount(source, destination)` compares values. `sameType(T, S)` compares the
types bound by `source::T, destination::S`; those types are known at compile time.
The current one-input guard implementation is not a reason to prohibit either
kind of relation in the language.

Predicate evaluation and method preference answer different questions while using
the same call machinery. The predicate answers whether a candidate applies.
The existing pointwise specificity, authored `<:`
priorities, caller-first context and ambiguity rules choose among applicable
candidates. If two different methods' predicates are true, an internal branch
order inside either predicate supplies no new preference between those methods.

Residual predicate facts, multi-input guard comparison, and effects remain OPEN
implementation work. Specialization must preserve observable execution and cannot
assume arbitrary predicates are pure or exhaustive. A predicate's own decision
needs a reachable default or coverage proof; its total boolean result does not
by itself prove that the surrounding method set covers every possible input.

## Start with the log viewer

RUNS, 2026-09-20: [log_labels](../tests/log_labels/test.md) displays log records
and routes messages that need attention to an operator:

```jpp
using Base
using Base.Zig

Level = Zig.std.log.Level

needsAttention(level::Level) = isOneOf(level, Level.err, Level.warn)

label(level::Level) where needsAttention(level) = "ATTENTION"
label(::Level) = "NORMAL"
```

`needsAttention` returns bool. A classifier returning text instead uses an
explicit comparison such as `where destination(level) == "operator"`.
The complete executable case separates the native type, policy, labels and
input fixture into modules, and runs a second caller context that includes debug
messages in the attention group. Every possible runtime enum case resolves before
the program runs. Removing the default leaves uncovered cases; overlapping
guards without precedence remain ambiguous in the winning module.

`isOneOf` is ordinary variadic library code using `==`. It tests membership
directly. It does not construct a closure or give module initializers a new stage;
the earlier `needsAttention = oneOf(...)` factory sketch is still unbuilt.

Each value qualifier currently refers to one fixed argument. Its ANF expression
is evaluated from the selected branch's known values and type/tag facts. Native
predicate calls require known arguments, and runtime data never becomes known by
being placed in a guard. Comma-separated guards compose pointwise; direct authored
predicate order and identical expressions supply refinement witnesses. Runtime
predicates, relational multi-input guards and whole-rest guards remain OPEN.

## Errors and payload sums use the same dispatch

RUNS: [error_dispatch](../tests/error_dispatch/test.md) reads a byte or produces a
native read failure. Ordinary methods handle success, end of input, and device
failure. Error-set annotations form native groups; exact error cases and value
predicates refine them. Missing possible outcomes fail compilation. A caller can
replace one error policy through the normal accumulated context.

Qualified error members must exist in their finite declared set. The same error
name has one native identity across sets. Error-union inputs establish either a
successful payload or a known error; handling or forwarding that error is an
ordinary method result, never an implicit return from the caller. Compatible
success/error results rejoin native error unions, merging error sets as necessary.
Runtime `anyerror` remains open and is rejected for automatic table injection.
Nested error-union inputs expose alternatives recursively, so an identity method
on those leaves can merge error layers. Compatible native nested results returned
by selected methods preserve their layers during result conversion.

[value_guard_variant](../tests/value_guard_variant/test.md) routes packet variants
through predicates on their selected type/tag. Payloads remain runtime data.
Tagged unions supply native payload-carrying sums; separate `Sum(...)` construction
syntax and general success-type unions remain unbuilt.

## The underlying structure

A method describes behavior on a region of the argument space. The caller's
context assembles these descriptions and determines preference where they overlap.
Specialization uses the facts already known about a call. A residual decision
program tests the distinctions still needed at runtime, then executes the chosen
body. A table is a way to understand this function, not a required array in memory
or a requirement to emit a dense Cartesian product.

A branch establishes a fact locally: this value has this tag, or lies in this
interval. That fact can become input to ordinary dispatch while the value remains
runtime data. An enum arm establishes an exact value; an interval arm establishes
membership without knowing the exact integer. These are different amounts of
knowledge. We should preserve the distinction in specialization.

For example, inside an interval arm the fact `x belongs to [0, 9]` is known,
while x itself is still unknown. Representing that fact must not fabricate an
exact static value, nor let the fact escape the branch without justification.

This connects enums, numeric cases and comptime evaluation. It does not require
enumerating all integers or floats, copying a collection, or recursing over its
elements. Runtime branching depth and collection traversal depth are independent.
Known selectors can remove branches while payload computations remain runtime.

The existing bridge is the exact-tag instance of this idea: it refines the pack
and invokes the ordinary resolver. It currently splits every direct enum/union
coordinate, even when subsequent optimization can merge equivalent work. Sharing
arms safely requires considering their specialized bodies and nested calls;
selecting the same outer method alone does not prove the arms equivalent.

## Native types, jpp wrapper

RATIFIED direction, 2026-09-19: the enum interface is a tight wrapper around Zig,
authored in jpp. This narrows the proposed case-family model from 2026-09-18 to
a native wrapper. The common idea is branch refinement and ordinary dispatch; it does
not require replacing native enums and tagged unions with one new value format.

Wrapping an existing enum preserves its actual Zig type, declared cases, tag
values and layout. Same-spelled cases from unrelated enums remain different
values. Reflection derives the cases from the native declaration, including
explicit tag values; the wrapper does not copy a handwritten list or renumber it.
It adds no required runtime storage. Native enum creation, if exposed, should
likewise be an ordinary library operation over Zig's type construction facilities;
its API and declaration identity rules remain OPEN.

The responsibilities are:

| Layer | Responsibility |
|---|---|
| Zig | Native representation, reflection and code generation |
| jpp enum library | Expose native cases and facts through ordinary words |
| Authored jpp methods | Compose behavior, shared definitions and contextual overrides |
| Dispatch machinery | Establish branch facts, resolve methods and emit remaining control flow |

An ordinary call is still the user interface. Passing two runtime enums can
produce nested implicit switches; a known case removes its test. The enum
wrapper must not demand explicit visitors, switches or value conversions at
every call. Merely calling Zig's existing Order.compare in a ground would not
meet the goal: its internal calls cannot acquire jpp context. The comparison
definitions themselves must live in jpp.

The chosen experiment is generic native primitives composed by jpp-only wrapper
bodies. Derive those primitives from desired source programs before implementing
a reflection API. The exact primitive set remains OPEN. No primitive may re-enter
dispatch with hidden caller context.
Base.Zig now exposes a native namespace root; generic static member access serves
namespace/type declarations and enum cases. Table injection remains in the core. Moving
all refinement policy into jpp needs reflection, static application and staged
branch construction; changing a file extension would not supply those features.

Known cases require only the selected arm; runtime cases require complete
coverage. Listing a non-exhaustive enum's named cases must not make it appear
closed. An arbitrary predicate collection also cannot establish exhaustiveness.
For unions, preserve the native owner and payload type. The current refined
Variant(owner, tag) with .payload is implementation evidence, not a requirement
to wrap plain enums in empty-payload objects. Whole-union annotations on refined
inputs and general result joins still need decisions.

## The working use case: reading DWARF offsets

RUNS, 2026-09-20: [dwarf_offsets](../tests/dwarf_offsets/test.md) replaces the
earlier comparison sketch as the first source milestone. A debugger reads section
offsets using a file's DWARF format (32 or 64) and byte order (little or big).
The native reference is Zig's private std.debug.Dwarf.readFormatSizedInt; the
fixture copies that small switch using the same std.Io.Reader primitives.

The dwarf facade contains:

```jpp
using Base.Zig
using Binary.Input
export Format, Endian, offsetType, readOffset

Format = Zig.std.dwarf.Format
offsetType(Format.32) = uint32
offsetType(Format.64) = uint64

readOffset(reader, format::Format, endian::Endian) =
    readUnsigned(reader, offsetType(format), endian)
```

The separate Binary.Input module contains:

```jpp
using Base.Zig
using Binary.Native
export Endian, readUnsigned, readUnsignedLE, readUnsignedBE

Endian = Zig.std.builtin.Endian
readUnsigned(reader, T::type, Endian.little) = readUnsignedLE(reader, T)
readUnsigned(reader, T::type, Endian.big) = readUnsignedBE(reader, T)
```

Binary.Native supplies two explicit IO grounds. Both return Reader.Error!u64;
the 32-bit read widens without changing sign. An ordinary call composes the
independent width and byte-order decisions. Inside each arm offsetType returns
a known type; no runtime-selected type escapes. Reader producers execute once
before selection and only one field is consumed. No enum list is duplicated.

The second caller context contributes an audit method only for
`readUnsigned(reader, uint32, Endian.little)`. It runs audit(), then the existing
readUnsignedLE leaf. The other three combinations retain their base behavior.
Tests cover all four combinations, high-bit unsigned values, truncated input,
native error propagation, sequential reads, producer order and selected-only
static coverage through helpers.

ReleaseFast LLVM inspection on aarch64-macos confirms the residual decisions:
runtime selectors retain width/endian branches; explicit static 32/little fields
leave one 32-bit load and zero-extension, plus reader buffer/error handling.
This is evidence for this compiler/target, not a claim about every optimizer.

The supporting source increment is deliberately bounded. Module constants admit
names, member paths, scalar literals and explicit grounds. Their values and
signature member paths resolve in the declaring module at comptime, with local
names preceding imports in source order. Re-export/folder/cycle aggregation
preserves identity, coalesces identical values and rejects conflicting values or
value/method collisions. Private constants stay file-local. Arbitrary initializer
calls, callable values, general static patterns and a staged branch library remain
unbuilt. The reader's slices, allocation and errors are native fixture details.

## Earlier comparison sketch (deferred)

OPEN source sketch, 2026-09-19, retained for its factoring idea. The user chose a
concrete binary-reader use case instead. Base.Zig, value bindings and member-path
patterns now run; this whole example still does not, including Base's comparison words.
The sketch reuses the existing explicit imports, packs and splats. Here Base.Zig
would export the native namespace root Zig, and Base would supply Any, == and ||.

```jpp
using Base
using Base.Zig
export Order, Op, accepts, compare

Order = Zig.std.math.Order
Op = Zig.std.math.CompareOperator

accepts(Op.lt) = (Order.lt,)
accepts(Op.eq) = (Order.eq,)
accepts(Op.gt) = (Order.gt,)

accepts(Op.lte) = (accepts(Op.lt)..., accepts(Op.eq)...)
accepts(Op.gte) = (accepts(Op.gt)..., accepts(Op.eq)...)
accepts(Op.neq) = (accepts(Op.lt)..., accepts(Op.gt)...)

compare(r::Order, op::Op) = oneOf(r, accepts(op)...)

oneOf(<:Any) = false
oneOf(value, candidate, rest...) = (value == candidate) || oneOf(value, rest...)
```

The accepted cases are ordinary small static packs. The six definitions describe
three elementary choices and three compositions. The recursion above reduces
these finite metadata packs; it is not an iteration strategy for runtime arrays.
The enum type and its cases come from Zig once. No jpp constructor duplicates
Order's declaration, and no compiler rule knows these comparison equations.

An application imports this module and can replace one cell with an ordinary
method: `compare(Order.eq, Op.lte) = false`. Calls inside other modules still see
that caller policy. The shared accepts definitions are also explicit extension
points; their compositions retain normal context propagation.

`compare(runtimeOrder, runtimeOp)` injects decisions for both inputs before its
body is selected. Inside each arm both cases are known, so accepts can return a
case-dependent static pack and oneOf can specialize to a boolean. With a known
operator only Order's choice remains; with both cases known neither choice needs
a runtime test. This describes intended specialization, not newly inspected
generated code. Identical branches may be merged by optimization.

The static boundary matters: calling `accepts(runtimeOp)` directly would require
a common runtime result representation for its differently shaped packs. The
example relies on its call occurring inside the refined compare body; it does
not silently add heterogeneous runtime return joins.

Working backward gives these requirements:

1. Generic native namespace/member access and stable value bindings. Looking up
   Order or Order.lt returns the original type or value. Enum case access should
   not require a separate compiler-owned constructor protocol.
2. General static value expressions in signatures. Op.lt denotes its actual
   declared value. It is not a fresh binder or a type predicate: every Op case
   has the same native type. Signature evaluation still needs an explicit stage
   and context rule; defining the signature must not execute a runtime producer.
3. Native reflection that supplies possible alternatives and tag/payload access.
   These are generic facts about native types. Enum-specific composition belongs
   in jpp. Generic type construction is needed when authoring new native types,
   but wrapping this existing enum does not require it.
4. A staged branch primitive that runs only the selected continuation under its
   established facts, evaluates producers once and retains the call's context.
   The library can describe splitting policy; the backend supplies branch regions.
   Passing eagerly evaluated branch results to an ordinary function cannot do
   this. Continuation/region representation and result joins remain OPEN.

The DWARF case above now supplies the first source milestone and contextual
override. Its bindings and case patterns constrain the native boundary before
moving the whole working bridge into jpp. Do not build a broad reflection library
without a consumer.

## A smaller source example: comparison

The selected specimen is Zig 0.16's installed `lib/std/math.zig`:
`Order.compare` at line 1572, `order` at 1615, and `compare` at 1668.
`Order.compare` switches on three relation values and six operator values: 18
boolean cells. It involves no storage, allocation, IO or traversal decisions.
`compare(a, op, b)` is the immediate follow-on: six operator arms with integer
or floating-point operands that can remain runtime data.

For the six ordinary numeric comparisons, operand pairs have four relevant
outcomes. This is a mathematical factorization of their results:

| Relation of the operands | `<` | `<=` | `==` | `>=` | `>` | `!=` |
|---|---|---|---|---|---|---|
| Less | true | true | false | false | false | true |
| Equal | false | true | true | true | false | false |
| Greater | false | false | false | true | true | true |
| Unordered (NaN) | false | false | false | false | false | true |

An operator accepts a subset of these outcomes. Four classes describe the
comparison results even though the operands range over a large numeric domain.
They do not describe every possible observation of those operands: the numbers
themselves must remain available to a body that uses them.

Zig's Order contains only the first three outcomes. Its `order(a, b)` checks
equality, less and greater, then reaches `unreachable` if none holds. It cannot
classify NaN. In that three-outcome domain, less-or-equal is the complement of
greater; for floating-point operands with NaN, that identity is false. Direct
`std.math.compare` uses native comparisons and preserves the unordered behavior.

For already evaluated scalar operands under ordinary strict comparisons,
greater can use less with reversed operands, greater-or-equal can use reversed
less-or-equal, and inequality can negate equality. These are possible authored
library definitions. The compiler must not impose such equations on arbitrary
overridable words: a caller's context can change their meaning. A four-outcome
classifier is likewise an optional library factoring, not a required compiler
primitive or necessarily the fastest way to execute one comparison.

| Facts available at comptime | Remaining work for numeric comparison |
|---|---|
| Operand types and operator | One selected comparison of runtime operands |
| Operand types only | Runtime choice among six specialized comparisons |
| Operands and operator, in a comptime evaluation | The boolean result |

Having a runtime operator does not require runtime method lookup. All six
implementations can be resolved in the static caller context. Conversely, a
known operator does not make unknown operands known. In current jpp, incidental
source literals remain data; this table does not introduce implicit static fields.

This example dispatches on an enum while operating on numbers. Direct numeric
case selection is a further step: exact values and intervals should describe
regions without generating one specialization per member. The existing
`spike/enumprobe.zig` uses `inline 0...9` and specializes each of ten values.
[Zig's inline switch semantics](https://ziglang.org/documentation/0.16.0/#Inline-Switch-Prongs)
explain why that validates only a small finite expansion. It does not establish
a scalable interval mechanism. Float cases must account for NaN and overlapping
conditions, regardless of whether the backend emits a switch or conditional branches.

## What belongs in the language

The proposed library boundary is reflection and construction of method/pack data,
ordinary context resolution, grouping/refinement, and explicit result-joining
policy. These are candidates for jpp comptime code. The execution substrate still
needs conditional regions: only the selected body runs, with facts valid in that
region. An eager function receiving two already evaluated results cannot provide
this behavior. The intended `src/ast.zig` has a region-based Select node, but the
active transpiler and body interpreter do not consume it.

The present `src/jpp.zig` bridge implements both refinement policy and branch
execution in Zig. Moving that policy into jpp needs supported reflection, static
application and staged body construction. Ordinary `zig{}` grounds must not gain
an implicit caller context to work around these missing facilities.

Value guards over known facts now run as described above. Runtime value guards
remain OPEN. Their evaluation/effects, overlap, coverage, refinement representation
and specificity need explicit rules. Start with a bounded pattern algebra;
arbitrary predicate programs cannot generally have their inclusion or
exhaustiveness decided by a compiler. The existing type-only
`<:` word remains type-only, pairwise and authored. It must not silently become
a numeric comparison or a theorem prover for runtime regions.

## Earlier source problem: JSON

The starting point is Zig 0.16's
[std.json.Value.jsonStringify](https://github.com/ziglang/zig/blob/0.16.0/lib/std/json/dynamic.zig),
lines 55–74 in the installed source. It switches over eight variants:

| Variants | Operation |
|---|---|
| bool, integer, float, string | write the payload |
| null | write null |
| number_string | write the payload as an unquoted number |
| array | write the items |
| object | begin, write each field and value, end |

The meaningful repetition is both the scalar writing rule and container
traversal. A tag remains semantically important: string and number_string have
the same payload type, but require different operations. Payload-type dispatch
alone is insufficient.

The user's rule is that ordinary calls inject the switch. The declarations
compose into the table in each caller context. There is no explicit visitor
operation, handwritten switch at the call site, or separate enum override system.

## The running jpp definition

These definitions are taken from `tests/json_dispatch/json/scalars.jpp` and
`containers.jpp`. All predicate and IO names are defined and imported from
`model.jpp`; the original std.json.Value declaration is used directly.

```jpp
using model
using json.traversal
export emit, openContainer, closeContainer, entries

emit(value<:JsonScalar, writer)::nothing = writeScalar(value.payload, writer)
emit(<:JsonNull, writer)::nothing = writeNull(writer)
emit(value<:JsonRawNumber, writer)::nothing = writeRaw(value.payload, writer)

emit(value<:JsonContainer, writer)::nothing = {
    openContainer(value, writer)
    walk(entries(value), writer)
    closeContainer(value, writer)
}

openContainer(<:JsonArray, writer)::nothing = beginArray(writer)
openContainer(<:JsonObject, writer)::nothing = beginObject(writer)
closeContainer(<:JsonArray, writer)::nothing = endArray(writer)
closeContainer(<:JsonObject, writer)::nothing = endObject(writer)
entries(value<:JsonArray) = arrayCursor(value.payload)
entries(value<:JsonObject) = objectCursor(value.payload)
```

Four scalar arms share a method. Arrays and objects share the entire container
body; their differences are small declarations for opening, entries and closing.
The shared `walk` in `json/traversal.jpp` consumes an immutable runtime cursor.
Its step is itself a tagged union: done, item or field. Dispatch injects another
table, and recursive `emit` calls preserve the caller's context. Field handling
adds the key-writing step; both kinds continue through the same walk.

`entries` can return different cursor types for arrays and objects because its
input is already a known variant inside the emit arm. The outer runtime emit
call has one result type, nothing. This is specialization doing useful work,
without forcing a common representation for every internal intermediate value.

## Overriding a region

`policy/masked.jpp` contributes one definition:

```jpp
using model
export emit
emit(value<:JsonString, writer<:Masked)::nothing = writeScalar("[redacted]", writer)
```

`policy/numbers.jpp` independently contributes:

```jpp
using model
export emit
emit(value<:JsonInteger, writer<:Masked)::nothing = writeIntegerAsString(value.payload, writer)
```

JsonString and JsonInteger are ordinary predicates. The model explicitly authors
their direct `<:` edges to JsonScalar. Masked is an ordinary writer predicate,
whose value also identifies the writer's static policy field. There is no
compiler recognition of these words. The override wins by pointwise dominance
on the variant and writer coordinates; ambiguity and context position retain
their existing meanings.

| Selected input | Base context, either writer | Custom context, Plain writer | Custom context, Masked writer |
|---|---|---|---|
| string | quoted payload | quoted payload | quoted `[redacted]` |
| integer | numeric payload | numeric payload | quoted integer text |
| bool / float | ordinary scalar | ordinary scalar | ordinary scalar |
| raw number | unquoted text | unquoted text | unquoted text |
| null | null | null | null |
| array / object | recurse | recurse | recurse with the same policies |

For the same input:

```json
[17,"x",{"name":"Ada","n":2}]
```

The custom context with a Masked writer produces:

```json
["17","[redacted]",{"name":"[redacted]","n":"2"}]
```

Plain writers still produce the original document in that context. Masked writers
also produce the original document in the base context, which has no overriding
methods. Object keys are written by the separately declared writeField word;
the string-value policy does not rewrite keys. Source dependencies, the package
facade, and declaration-only requirements remain explicit.

## What the implementation proves

The machinery refines one direct call coordinate at a time, then resolves the
same word on each refined pack. A plain enum is a static enum field in that arm;
a union is a Variant(owner, tag) value carrying its payload. A generated variant
cannot be forged just by copying metadata. Its runtime representation is a
shallow payload copy; this does not invent ownership or extend referenced data's
lifetime. Existing predicates can group variants and context can refine them.

Known tags select only their arm. Runtime tags require all arms, with ordinary
ambiguity checks. Only the selected body executes; producer effects are not
repeated across possible branches. Named fields, splats, static values and
private declaration homes survive the same binder/context path. Multiple enum
coordinates generate nested tables. Plain records are not recursively split.

Correction, 2026-09-17: the original bridge discarded static result information
after selecting a known union arm. Extracting a payload into an ordinary helper
could therefore prevent later specialization. `callInfo` now follows the known
arm's refined call and preserves its result metadata. The `variant_static` case
checks helper composition, named/rest forwarding, a returned known union used
for selected-only coverage, and execution of runtime effects exactly once.
Unknown arms still produce runtime data; this adds no general constant folding.

The result must have a common runtime type. Returned variants of the same union
can rejoin their original union, preserving `identity(x) = x`. Other implicit
result joins are not implemented. A runtime-selected type cannot escape.
A native exact `::U` signature does not itself describe U's variant family:
family coverage in this increment is written as a predicate. That boundary needs
review alongside eventual enum/type declaration syntax.

## Evidence and limits

The case uses ten jpp source files, two fresh program contexts and two writer
families, with 38 assertions passing in Debug and ReleaseSafe. It compares the base serialization with std on all eight variants,
including escaping, arbitrary-precision raw numbers, empty and nested containers,
and runtime arrays of 0, 1, 8 and 128 elements. It also checks the two independent
policies and bounded-output failure. Separate cases reject missing arms, unrelated
owners, crossing specificity, incompatible results, runtime type escape and
non-exhaustive enums. The native resolver tests additionally cover exact enum
values, multiple enum coordinates, delegation and signature set operations.

The adapter is currently more code than Zig's original serializer method. What
has become smaller is the set of shared behavior bodies and the cost of adding
an override. We should not count parser/writer/type-adapter boilerplate as solved.
The model still uses Zig for union reflection, type constructors, cursor access,
parsing, allocation and writing primitives. The jpp layer owns the dispatch,
composition and recursive traversal. No ground re-enters jpp with a hidden context.

This is a research case, not a replacement JSON library. Its writer is fixed to
at most 8192 bytes and inherits std's safety-mode depth limit. It records the first
write error; cursor advancement and further IO stop after failure, while already
entered jpp frames unwind normally. Native error-set/result joins now run in
the separate reader case. General `try`, allocator policy, mutable borrowing and
guaranteed stack bounds remain separate work.
Parsing malformed input is outside the corpus and fixture allocation failures
panic. The 128-item case proves runtime-sized iteration, not arbitrary recursion
scaling or a fixed stack bound.

The Zig arrays, maps and cursor adapter are foreign fixture details, not a choice
of jpp's collection model. The objective here is multiple dispatch replacing a
switch. The host implementation also does not establish that table construction,
variant representation and result-joining policy must permanently live in Zig.
Moving those into ordinary jpp compile-time code is a design direction to examine;
the active surface still lacks the reflection, callable application and staged
branch construction needed to express the complete mechanism without Zig grounds.

## Next small increments

1. Completed: native namespaces, module constants and enum member-path patterns,
   exercised by the modular DWARF reader and an inner caller override.
   Known-fact value guards and native error-set/error-union tables now also run,
   with coverage in log labeling, file-header validation and packet routing.
2. Define the stage/context rules for ordinary static application before allowing
   calls in module initializers or signature patterns. Existing member paths are
   lexical; extending them must not accidentally change declaration identity.
3. Use the reader to specify the smallest reflection and staged-branch primitives
   that let a jpp library express the remaining enum refinement policy. Preserve
   explicit continuations, producer evaluation and native error result identity.
4. Numeric cases and symbolic interval refinement remain separate research.
   The comparison analysis records NaN constraints but is not the next required
   feature. Runtime guards and unrelated successful result joins still need
   explicit decisions.

JSON expansion and large-array experiments are paused. Its foreign representation
and recursive walk do not settle the language's memory or iteration model. The
next proof should isolate dispatch, specialization and ordinary library factoring.
