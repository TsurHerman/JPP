# Callback types follow actual invocation facts

A callback does not split runtime enum inputs merely to enter its fixed body.
The identity callback preserves runtime field metadata, including for an unnamed
value of a non-exhaustive enum. A body that selects a type must propagate that
demand to its continuation, both from its direct input and a captured runtime
enum. The reader consumes the chosen type inside a concrete branch and returns
an ordinary uint64 result.
