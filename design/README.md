# jpp design notebook

This folder describes the language we intend to write libraries and binaries in.
The root [README](../README.md) remains the decision ledger; [tests](../tests/README.md)
are executable promises. A plausible sketch is not evidence that a feature works.

Read in this order:

1. [Modules and units](modules.md): source visibility, folder imports, explicit
   Base, and mutual imports. Public composition and private ownership are separate.
2. [Packs and calls](packs.md): values, static fields, named inputs, and the next
   dispatch decisions for varargs. One representation serves code and data.
3. [Implementation sequence](generality_plan.md): completed slices, evidence, and
   remaining work. Every slice must improve a real modular program.
4. [Word contracts](word_contracts.md): declaration-only exports work; stronger
   argument/result obligations are a later interface feature.
5. [Type families](type_families.md) and [numerics](numerics.md): future libraries,
   with unresolved policies identified rather than hidden in pretend implementations.
6. [Binary units](binary_units.md): what an inspectable compiled unit must retain.

**Status vocabulary:** RUNS means implemented and checked through the active
pipeline; VALIDATED means machinery/probe evidence; RATIFIED means decided but
unbuilt; OPEN marks a decision still needed. The implementation plan records
the checks supporting completed slices.

The former loose `.jpp` sketches have been replaced by these documents. They
mixed unavailable syntax, undeclared dependencies, outdated `core` imports, and
unchecked conversions with language decisions. Their history remains in git.
Runnable examples belong under `tests/`, especially `checkout`, `pack_values`,
`named_context`, and `declaration_tunnel`.
