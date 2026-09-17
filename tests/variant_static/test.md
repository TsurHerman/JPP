# Known branch facts survive helper calls

A call on an explicitly static tagged union selects one arm. If its ordinary
body returns a known payload, the result retains that static value through
local aliases, named calls and rest forwarding. Extracting an expression into
a helper must not discard information already available at comptime.

A returned known union retains its tag: the next call can require just that
arm's method and return a type, even though other arms have no implementation.

Retaining a static result must still execute the helper's runtime effects once.
A runtime union's payload remains runtime data, even when a producer happens to
receive a literal. This does not add constant folding across unknown branches.
Mixing a known union with a runtime union must leave the second payload dynamic.
