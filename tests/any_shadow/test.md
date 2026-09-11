# any_shadow

A tree's `Any.jpp` shadows `Base/Any.jpp` through ordinary module lookup.
Its exported predicate, here accepting only bool, determines applicability.
Base's membership and order methods must not be injected by the compiler.
