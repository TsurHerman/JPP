# Word contracts and context-selected implementations

Status: **OPEN — research recommendation, not implemented or ratified.**
Reviewed against the current compiler and language cases on 2026-09-11.
The separate explicit `Any` change is RUNS; it does not implement contracts.

## Recommendation

Require a source-visible callable contract for dependencies. Allow that
contract to exist without an implementation. Make a real base implementation
optional, and require an applicable implementation at each concrete call.

This distinguishes three questions:

1. **Declaration:** which existing word does this source refer to?
2. **Contract:** what argument packs and result constraints does it describe?
3. **Execution:** which implementation does this accumulated context select
   for this concrete pack, and does its result satisfy the contract?

Checking only that a callee's spelling occurs somewhere answers too little.
Requiring every word to have a catch-all body answers too much: it forces
behavior for cases where the operation may have no meaningful answer.

For `probe(x) = tag(x)`, the library must state its dependency on `tag`.
Caller context may select `base` or `loud`; it must not manufacture the
library's missing declaration. A misspelling such as `tga(x)` should be a
declaration error even if some caller happens to export that spelling.

## Evidence from other languages

| Model | What it separates | Lesson for jpp |
|---|---|---|
| Julia empty generic function | A function can be introduced without methods. The empty declaration supplies no argument/result signature. | Declaring a name need not supply behavior, but name existence alone is weaker than the contract sought here. [Julia methods](https://docs.julialang.org/en/v1/manual/methods/#Empty-generic-functions) |
| Dylan explicit generic function | A typed generic declaration has no executable body. Method parameter and result declarations must conform to its protocol. Multiple arguments participate in dispatch. | Closest precedent for a typed word surface separate from its methods. [Generic functions](https://opendylan.org/about/examples/generic_functions.html), [parameter-list congruency](https://opendylan.org/books/drm/Parameter_Lists#parameter-list-congruency) |
| Rust trait | Required functions can omit bodies; provided bodies are defaults. Generic items can state trait bounds. | A requirement and a default are independent facts. [Rust traits](https://doc.rust-lang.org/reference/items/traits.html) |
| OCaml module signature and functor | A dependency's types and operations can be known while its implementation is supplied through a module parameter. | A library can be reasoned about with an explicit dependency interface before an implementation is available. [OCaml functors](https://ocaml.org/docs/functors) |

These are precedents, not specifications for jpp. In particular, importing
their subtype hierarchies, global method tables, coherence rules, or module
parameter syntax would change jpp. The recommendation below is an inference
from their separation of declarations, obligations, and implementations.

## Why a mandatory catch-all body is the wrong requirement

Consider three possible bases for a word:

- `tag(::Any) = 0`: supplies an actual answer for every accepted input. This
  is appropriate only if zero is the intended fallback meaning. Otherwise
  an uncovered implementation becomes an apparently successful computation.
- A catch-all that raises an error: records a failure path rather than an
  implementation. It must not count as proof that the required operation
  exists. A compiler-managed missing-implementation obligation describes
  this more directly and can identify the requiring library and call pack.
- A typed declaration without a body: states a protocol and contributes no
  candidate to dispatch. It cannot win a tie, resolve an ambiguity, or
  suppress a missing-method error.

A useful real default remains welcome. For example, a classification word
can intentionally return false outside its specialized cases. Requiring
that default for *all* words confuses an author's chosen semantics with a
compiler's need to validate references.

`Any` is a universal input domain, not evidence of implementation coverage.
`::Any` may be ignored because its domain is explicit; `x::Any` may retain a
name. Reading the name in the body is not a proof that the dependency is
valid, that the result is correct, or that every input has an implementation.
The unused-input diagnostic is a small guard against accidental generic
declarations such as undefined `Signed`/`Wide`; it is not a contract system.

## What a contract should say

For the existing integer `tag` example, the minimal dependency is:

> There is a word `tag` accepting one integer input and returning an integer.

A generic library can instead require `tag` for its bound input type `T`.
That is a conditional obligation for each specialization. It must not be
reported as proof of a total operation on every member of `Any`.

One possible spelling is a signature without `=`:

```text
# Proposal only — the current parser requires a body.
export tag
tag(::Any)::int64
```

Here the surface describes the permitted family of implementations; it does
not certify that a context covers every input. Documentation and diagnostics
must say that concrete calls still require implementations. A narrower
`tag(::int64)::int64` contract states less and should be used when that is
the library's actual requirement. Parametric dependencies need explicit or
inspectable obligations; the exact syntax remains undecided.

Do not infer an entire open word's allowable domain from one imported method:
`tag(::int64) = 1` describes one implemented domain, not necessarily the limit
of every future `tag` extension. A local implementation can provide evidence
for its own calls, but it does not automatically establish a universal word
contract. This is why merely adding `using base` is an immediate lexical
repair, not a complete answer to the interface design question.

Contracts may need multiple signatures for different arities and domains.
One catch-all signature would unnecessarily restrict words that legitimately
support several pack shapes. The surface should expose input sections,
fixed type values versus type domains, type variables, gates, and result
constraints using the same pack vocabulary as method declarations.

## Checking without changing dispatch

Proposed validation stages:

1. **At declaration:** resolve each ordinary callee and gate word through
   the declaration's lexical home and imports. Check visibility and contract
   shape even when the containing method is never instantiated. Later caller
   imports cannot repair an undeclared reference.
2. **For a generic body:** retain requirements involving its bound types as
   explicit obligations. A dependency report should show their source and
   pack/result constraints, rather than just a list of word spellings.
3. **At concrete instantiation:** resolve implementations using the existing
   caller-first context, pointwise dominance, and position rules. Reject a
   missing implementation, ambiguous winner, or violated result constraint.
   Validate obligations before producing an executable instance.

A declaration without a body never enters the implementation candidate set.
Do not silently discard a selected method and choose another when its body
has an unsatisfied dependency: that would change applicability and dispatch
semantics. An explicit capability gate could request such filtering, but
that is a separate design decision.

The contract must constrain the implementation selected from the caller's
context, not merely the library's fallback. For example, a declaration that
promises an integer result cannot be satisfied by a caller override returning
a string just because the base method returns an integer.

## jpp-specific constraints and unresolved decisions

- **Order is not semantic inclusion.** An authored `<:(Signed, Wide)` fact
  controls pairwise preference; it does not prove that every Signed member
  passes Wide's predicate. Existing `sigLeq` machinery uses authored order
  for predicate comparisons and therefore cannot by itself certify contract
  substitutability. Concrete pack checks and result checks are sound evidence
  for that instance. Universal implication between arbitrary predicates needs
  a separate proof or explicitly trusted obligation; it cannot be inferred
  from spelling, rank, or a missing transitive edge.
- **Word identity and fusion:** exported implementations currently fuse by
  word name. Requiring shared nominal contract identities would change that
  rule. Decide how compatible contracts imported through different modules
  compose, and how incompatible ones fail. They should not silently win by
  context position; implementation priority is not contract compatibility.
- **Module checks versus specialization checks:** name/shape validation can
  happen early. Generic coverage is conditional until types and context are
  concrete unless an additional proof system is adopted. Diagnostics and the
  ledger must make that boundary visible.
- **Predicate context:** decide whether a contract's predicates are evaluated
  in its declaration context or in the caller's accumulated context. An
  override of a predicate can change the accepted domain itself. This must
  be an explicit property of the contract, not an accidental consequence of
  reusing the method resolver.
- **Type-only words:** `<:` already has a machinery-defined type-only domain,
  boolean result requirement, and pairwise floor. It is a useful first
  built-in contract example; it does not justify injecting runtime values
  into type positions or adding transitive closure.
- **Binary development:** the future artifact format must carry contracts
  and dependency obligations alongside method data. An already-compiled
  instance needs either compatible replacements or invalidation and rebuild
  when a relevant contract changes. The existing parser/runner does not yet
  implement this binary loading or invalidation infrastructure.

## Implementation sequence and acceptance cases

1. Ratify the distinction between a declaration and a candidate body, the
   meaning of partial coverage, and how contract identity follows exported
   word fusion. Choose syntax after these semantics.
2. Add contract metadata and source locations to emitted data. Keep jppc
   file-local and context-blind; the comptime machinery checks lexical
   visibility and contracts. Do not encode a declaration as a dummy ground.
3. Add declaration checks and concrete call/result obligations. Preserve
   declaration homes through folder aggregation and include contract
   dependencies in the future instance key and diagnostic report.
4. Repair `override` and `caller_context` to declare their dependencies,
   preserving their existing answers. Add focused cases for:

   - undeclared calls in both used and unused methods;
   - declaration-only dependency with a caller implementation;
   - declared word with no applicable implementation;
   - wrong arity, runtime input to a type-only word, wrong result type;
   - valid caller override without changing the dependency surface;
   - optional meaningful fallback and a still-uncovered call without one;
   - generic specialization whose required operation is missing;
   - imported/private visibility and declaration homes through aggregation;
   - conflicting contracts and preserved same-module ambiguity;
   - an authored order fact that does not imply predicate inclusion.

Until these decisions and tests land, the repository should describe its
current no-import examples as context-dispatch probes with a known lexical
dependency gap, not as proof that a library has a complete checked interface.
