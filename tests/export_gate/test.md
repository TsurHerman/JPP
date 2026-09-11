# export_gate (negative)

**Validates (README §1):** exports gate everything. `secret.hidden`
has no `export` line, so it emits non-`pub`; `using secret` then
calling `hidden(7)` must FAIL to compile with the same error as a
word that does not exist — the substrate enforces the boundary, and
nothing about the internal leaks. `expect.err` greps
`no method 'hidden' matches in context`.
