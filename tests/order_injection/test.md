# One authored priority resolves an overlap

An int64 input satisfies both `Integer` and `Signed`. These same-module methods
therefore compete at the same predicate rank:

```jpp
category(::T) where T <: Integer = 1
category(::T) where T <: Signed = 2
```

This case adds exactly the priority the library needs:

```jpp
<:(Signed, Integer) = true
```

`category(1)` must select the Signed method and return its marker, 2. The
[where_gate_clash](../where_gate_clash/test.md) case keeps the same overlap but
omits this edge, so compilation must fail.

The edge is an ordinary method whose arguments are defined predicate values.
It can be provided or overridden by caller context; `order_refines` shows an
edge in a separate module. The compiler checks authored pairs directly and
does not infer transitive links or prove relationships from predicate bodies.
