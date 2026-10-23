# Named callable context and stable word identity

Bare function and operator expressions produce callable references in the
effective context where the value is obtained. A module alias to a word identity
does the same when used. Passing, returning, locally binding, or storing an
existing reference preserves its context rather than capturing another one.

The main module's `transform` calls `adjust`. A reference created in main returns
10, while one returned by the maker sees its extra module's more specific policy
and returns 100. Passing main's reference through the maker still returns 10.
The difference reaches calls inside the selected method, not just its entry.

Word identity remains independent of this invocation environment. Native
`::type` inputs, including rest elements, receive the canonical identity;
exact word patterns match that identity while retaining the supplied callable
reference for their bodies.
Repeated exact patterns, predicate aliases, `Any(Integer)`, and authored order
continue working. The order operator itself can be passed and retains its
intrinsic identity rule. `Function` remains an ordinary predicate. Reflection
reports source locations and the same named identity across contexts, and uses
the shared resolver. These promises do not define callable value equality or
equate differing behavior.
