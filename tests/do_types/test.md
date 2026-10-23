# Callback specialization and one-body signature checks

A do block uses the existing pack binder to validate one selected body. Its
parameters support exact types, type variables, predicates, named inputs, and
positional/named rest. Repeated calls specialize that same body independently;
no callback overload is selected.

Captures preserve enclosing where-bound type identity. A do block has its own
sequential binding scope: parameters and new locals can shadow outer locals,
and body bindings do not leak. Defined module names in the callback signature
retain their existing exact-value meaning, just as ordinary method signatures
do. Annotated inputs may be unused.

The written receiving-call arguments run before construction of the trailing
closure. Its value is then inserted as logical argument one. A binding created
inside a preceding argument's ordinary block is therefore available to capture.
