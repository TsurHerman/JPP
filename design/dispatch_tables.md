# Methods describe cases; specialization builds control flow

Status: automatic enum/tagged-union calls RUN in the active machinery. The
serialization case below is executable jpp, not proposed syntax. Plain enum
value patterns are currently native method data; enum declaration/pattern
surface syntax remains unbuilt. Revised 2026-09-15.

RATIFIED principle: a branch establishes a fact that ordinary dispatch can use
inside that branch; knowing the fact at comptime removes the runtime test.
The value itself may remain runtime data. General fact representation, syntax
and runtime-predicate rules below remain OPEN. This does not claim that the
implemented enum rule already supports arbitrary runtime predicates.

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

General value guards remain OPEN. Their evaluation/effects, overlap, coverage,
refinement representation and specificity need explicit rules. Start with a
bounded pattern algebra; arbitrary predicate programs cannot generally have
their inclusion or exhaustiveness decided by a compiler. The existing type-only
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
entered jpp frames unwind normally. General `try`, error-set joins, allocator
policy, mutable borrowing and guaranteed stack bounds remain separate work.
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

1. Give already declared enum values an explicit usable surface identity and
   exact patterns. Undefined names must remain binders, never invented tags.
2. Reproduce Order.compare through source modules; check all 18 cells with known,
   runtime and mixed selectors. Factor shared definitions before adding policy.
   A separate application word, such as acceptsBound, can delegate comparison
   and let an open-bound policy replace its equality cases in a second context.
3. Extend that scalar case to numeric operands and six operators. Cover integers,
   floats, signed zero, infinities and NaN, plus producer order and single
   evaluation. Inspect known-operator and runtime-operator generated code.
4. Use that evidence to design symbolic interval refinement and the smallest
   staged branch primitive needed by ordinary jpp libraries. General value guards
   and result joins require separate decisions before implementation.

JSON expansion and large-array experiments are paused. Its foreign representation
and recursive walk do not settle the language's memory or iteration model. The
next proof should isolate dispatch, specialization and ordinary library factoring.
