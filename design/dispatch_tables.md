# Declarative methods become an injected table

Status: automatic enum/tagged-union calls RUN in the active machinery. The
serialization case below is executable jpp, not proposed syntax. Plain enum
value patterns are currently native method data; enum declaration/pattern
surface syntax remains unbuilt. Revised 2026-09-15.

## The source problem

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

1. Review an enum declaration and value-pattern spelling against this running
   package; preserve names as real definitions, not implicitly invented tags.
2. Make variant reflection and group membership comfortable ordinary library
   code, and settle exact owner-type annotations on refined inputs.
3. Use the writer failure path to design error propagation, then measure long
   arrays and deep recursive documents before broadening collection promises.
4. Bring these concrete requirements back into static type application, callable
   types and native-field declarations in the generality plan.
