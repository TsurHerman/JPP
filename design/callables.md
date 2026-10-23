# Callable values, do blocks, and reflection

Status: RUNS, ratified and implemented on 2026-10-23. `do_blocks`, `do_types`,
`do_enum`, and `reflection` provide executable evidence. This document
distinguishes the agreed semantics from broader callable, ownership, and
reflection work that remains OPEN.

## One value, one environment

A closure consists of an anonymous body identity, its lexical declaration home,
the effective dispatch context at construction, and captured values. Its native
representation is a callable struct. Code identity, home, context, captured type
values, and explicit static facts are compile-time information. Ordinary captured
data stays runtime data even when its binding is immutable.

Mathematically, a body is a family of maps `B_C : E × A -> R`. Closure construction
fixes the environment `e` and context `C`; application supplies the argument pack
`a`, giving `B_C(e, a)`. Selecting a body and specializing that body are separate
operations. An anonymous closure has one body, which can specialize independently
at different input types. Calls inside that body still use ordinary jpp dispatch.

The surface convention is:

```jpp
using Base

F(f, a, b) = f(a, b)

F(2, 3) do x, y {
    x + y
}
```

The trailing `do` expression constructs the anonymous callable and inserts it
as the first positional argument. Existing arguments retain their order and
named section. `do { ... }` constructs a zero-argument callable. Parenthesized
`do (x, y)` is not an alternative spelling for two inputs; tuple destructuring
remains separate work. The body returns its last expression.

The receiver determines the supplied values and therefore the callback input
types at each invocation. Its selected method is established first. An invalid
callback body is an error at that invocation; it never makes the receiver retry
a less preferred method. Callback annotations validate its one signature rather
than introduce an overload set. Existing unused-input rules remain in force:
unused bare inputs, including `_`, are invalid; annotations can give them a role.
No compiler-special `Function` nominal type or type erasure is required.
The initial callback grammar supports positional/named/rest inputs and its own
`where` type binders. Exact annotations name builtins/module types or those own
binders; annotation types captured from enclosing local bindings and dotted
exact enum/error patterns remain unbuilt. Existing module-defined bare values
retain their exact-pattern meaning, including repeated exact values.

## Context and lexical scope

Capture the caller-first accumulated context active at construction, together
with the original lexical home. A closure created by library L under application
A retains A's applicable policies and L's lexical declarations. Passing it to
library R does not add R's later context to the closure body. Ordinary word calls
inside the body still accumulate their own callee imports in the existing way.

The body has its own parameter/local environment. Free locals must be available
at construction; later outer bindings remain forward references. Nested closures
capture the appropriate enclosing values. Body-local bindings do not escape into
the creator. Private helper identities and known-member validation retain their
declaration homes, including through folder aggregation and import cycles.

Captures contain existing ANF values. Their producers are evaluated once and in
source order. Construction does not execute the body. Capturing a value does not
create a reference to an enclosing stack slot. Copying a closure copies its
environment using ordinary value semantics; pointers and slices retain their
native referent/aliasing behavior. This is shallow capture, not lifetime checking.

The receiving function controls whether and how often the body runs. `do` adds
no implicit cleanup, error propagation, early return, laziness, or asynchronous
scheduling. Returning a closure preserves its captured values and context, but
does not prove that borrowed native resources remain alive.

## Named words keep their method families

`bindword(f)` explicitly constructs a context-bound callable for a lexically
declared word. It captures the effective context and the word's lexical identity.
Calling it resolves that word normally in the captured context. Unlike an
anonymous callback, it intentionally retains a method family.

Bare word values keep their existing class/predicate identity. The explicit
binding form prevents passing an ordinary predicate identity from silently
changing authored order or signature semantics. A lexical local with a matching
spelling cannot silently redirect a value application to a module word. A
non-callable value produces an error.

## Reflection is language data

Reflection describes actual callable values and concrete call facts through
ordinary imported library words. The initial interface is `Base.Reflection`:
`reflect(f)`, `analyze(f, pack)`, and `returnType(f, pack)`. The pack is an explicit
two-section value, preserving static fields and runtime field types.

Description includes callable kind, body or word identity, original lexical home,
source provenance, captured dispatch context, and capture descriptors. Static
facts are distinct from runtime values: passing the type value `int64` is not
passing an integer whose type is `int64`.

Call analysis uses the same selection engine as execution. Its structured outcome
distinguishes selection, no applicable method, ambiguity, and cyclic strict order.
Candidate evidence records binding and qualification failures and pairwise
dominance/context decisions. The intrinsic `<:` identity and default rules are
reported as `order_identity` and `order_default`, without an invented method
index. A runtime case-sensitive call must report its branch
obligation or an explicitly incomplete analysis, never a fabricated single winner.
Ordinary execution turns unsuccessful outcomes into the existing diagnostics.
The initial interface reports `incomplete` for bound-word analysis requiring
runtime enum/sum branches; it does not yet expose those branch plans or a
coordinate-by-coordinate dominance proof.

Selection, body type checking, and universal contracts remain different claims.
Return inference is a separate query after selection. Reflection must not execute
runtime input producers or the callback to discover facts. Ordinary supported
compile-time qualification remains subject to the existing staging rules.
Metadata does not grant access to undeclared/private words. Inspection is
observational: it does not introduce runtime evaluation or mutable method tables.

The same typed facts can support human-readable diagnostics, editor navigation,
and agent tools. Source locations and identities belong to callable metadata from
the first implementation. General AST quotation, macros, a stable external
inspection protocol, and persistent binary identity remain OPEN.

## Implementation obligations

The frontend remains file-local and context-blind. Closure construction,
application, and word binding are distinct ANF operations; semantic context and
type decisions stay in the native machinery. Nested bodies participate in
lexical call/member validation even when they are never invoked.

Context dependencies must survive before construction, including dependencies
used only by a nested or returned callback. Reflection makes captured contexts
observable. The initial implementation may conservatively retain the complete
effective context for paths that create callable values, rather than applying
an unsound collapse. Any later reduction must preserve both execution and the
documented reflection observations.

Application alone does not demand enum enumeration. Inner dispatched calls and
type-valued intermediate results can demand refinement under the captured context.
Static facts, source evaluation once, existing result joins, and the distinction
between direct inputs and fields hidden in records remain in force.
An enum captured inside a callable may select a type consumed inside that body.
Returning that selected type to a receiver is rejected when it would require
lifting a runtime split through the callable's hidden environment; see
`do_captured_type_escape`. Explicit static captures can return types normally.

Specialization identity includes body identity, home, context, environment field
types/static facts, and argument field types/static facts. Runtime environment
contents do not become additional code-generation keys. This representation
requires no general runtime function registry or implicit heap allocation.

## Deliberate remaining boundaries

General user-authored callable-struct syntax and overloaded `()` methods, shared
mutable function statics, ownership/call-once capabilities, async transfer,
heterogeneous erased callback storage, callable equality, and recursive local
bindings remain OPEN. Runtime callback evaluation in guards is rejected under
the existing known-facts staging rule. The representation leaves room for these
features without selecting their policies implicitly.
