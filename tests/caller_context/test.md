# caller_context

**Validates (README §1):** dispatch is caller-derived. `algebra` currently
imports nothing; callers supply arithmetic implementations, and the same
generic `double` serves every domain the context grounds. Two checks:
caller implementations are used, and the generic method generalizes.

The missing lexical dependency on `+` is a current gap. This case proves
context dispatch, not a checked library interface. The contract proposal
must preserve these computations with an explicit dependency surface.
