# Callback bindings do not enter the creator

An ordinary block shares its enclosing method's sequential environment, but a
callback is a distinct body. Its local bindings are unavailable after creation
and remain unavailable even after an invocation.
