# Independent log records do not multiply tables

A dashboard counts twelve records that need attention. Each record has one of
four native log levels. The coordinator forwards each level independently to
`attentionScore`, so it needs twelve calls to a four-case decision, not a table
of 4^12 combinations.

The test inspects the coordinator's argument pack: all twelve fields must
remain runtime data. A native witness rejects runtime execution of the `where`
predicate; the score and label calls still decide applicability at comptime.
All twelve producers run exactly once.

The smaller checks cover forwarding through rest and named arguments, a method
that really does require two cases, and pruning a later split when an earlier
case or known guard rules that method out. `open_transport` also passes an
unnamed native enum value through generic code: no table is needed there.
`enum_open` continues to reject case-sensitive dispatch on an open enum.

`type_selection` decodes a binary offset using a type chosen by its native
32/64-bit format. Three incidental log policies reach the same type helper before
the format argument. Only the format needs specialization: those policies stay
runtime, and all six policy producers across two reads execute once.

This removes eager products for unrelated enums. Truly interacting inputs can
still require combinations. Tagged unions and native error inputs retain their
existing eager representation refinement in this increment.
