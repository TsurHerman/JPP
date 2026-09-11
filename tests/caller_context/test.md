# caller_context

**Validates (README §1):** the same generic `double` serves integer and float
domains. `algebra` now receives a source-visible `+` through implicit Base;
the caller's explicit arithmetic providers coexist ahead of that import.
The answers here agree with Base; `base_import` and `depth_override` use
different answers to prove which implementation wins.

The implicit import supplies this particular lexical dependency. General
callee validation and checked callable contracts remain unbuilt.
