# A runtime shipment cannot choose a compile-time type

The two methods choose `int64` for express shipments and `float64` for standard
shipments. Such type selection is useful only when the tag is already known
at compile time. Here the incoming shipment is runtime data.

Compilation must reject a runtime-selected, compile-time-only result. A fixed
express input succeeds in [variant_dispatch](../variant_dispatch/test.md);
this case keeps the opposite boundary explicit.
