# module_encoding

Module identity is independent of generated filesystem spelling. `Base` and
`base` must stay distinct on a case-insensitive filesystem, and `a.b` and
`a_b` must not create the same Zig import alias. Aggregate and dotted imports
share the intended module while preserving distinct source paths. Source
modules named `jpp` or `run` must not overwrite the runtime or driver. A
capitalized program name exercises the same encoding in the generated harness.
