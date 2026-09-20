# An unvisited error row still has to resolve

The native reader returns info, whose label is unambiguous. The `where` guards
require a case distinction, and the runtime result type permits every log
level. The error case matches two predicates with no authored precedence.
Compilation must identify that conflicting case before the program can run.

Demand-driven splitting does not weaken coverage or ambiguity checks when a
split is needed. Compare `enum_guard_missing` for missing runtime cases and
`enum_guard_ambiguous` for ambiguity at a comptime-known error value.
