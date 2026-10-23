# Named callbacks keep the passing site's dispatch context

`F(twice, 3)` passes the named function directly. Its selected implementation
calls `policy` internally. The receiving module has a more specific `policy`,
but that later context must not enter the callback. An equivalent do block
and the named function therefore return the same answer.

`sort(<, V)` and `sort(V) do a, b { a < b }` both sort ascending, even though
the receiving module's own `<` sorts descending. The sort is generic over its
comparator and native fixed array. Native arrays and std.mem.sort are foreign
fixtures; this case does not choose a jpp collection or ownership model.

Aliases, returned callbacks, forwarding, private homes, and record projection
retain the saved context. Function membership and reflection work directly on
the named value, with no explicit binding syntax. Reflection in the receiver
identifies the provider selected in the callback's captured context.

A separate root uses Base's ordinary int64/float64 comparison methods and other
operator values. Another composes runtime enum type selection through a named
callback and transports an open enum through a generic named identity without
enumerating it. These programs start with independent caller contexts.
