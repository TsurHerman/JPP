# Two ordering enums are not interchangeable

A comparison helper accepts the `lt` case of Zig's `std.math.Order`. A database
adapter independently declares its own enum with the same `lt`, `eq`, `gt`
names. Passing that adapter's `lt` must not match the native case pattern.

Compilation fails at `isEarlier(DatabaseOrder.lt)`. Matching tag spelling does
not discard the enum owner. An explicit adapter could translate the database
order into the native order; dispatch must not invent that translation.
