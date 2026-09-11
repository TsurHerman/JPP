# collapse_imports

The caller imports only a facade and, in one program, a policy. The facade
reaches `tag` through three further import boundaries. Collapse must retain
the caller's `tag` override before those deeper modules enter the context.
Every call has a real local or imported definition in its source module.

Dependency discovery must not make those deeper imports participate in
resolution early. The facade's bare `surface` method still answers at the
root, even though a deeper module defines a more specific exact method.

This isolates the checkout failure: following only bodies in modules already
in the caller's context silently discarded the member policy.
