# any_shadow

A tree's `Base/Any.jpp` shadows the bundled `Base.Any` leaf through exact
module lookup. Its exported predicate, here accepting only bool, determines
applicability. The main module explicitly imports `Base.Any` and `Base.Test`.
Bundled membership and order methods must not be injected by the compiler;
an explicit declaration of `<:` permits the ordinary absent-edge query.

A second program imports the Base facade and checks that the same
source leaf replacement participates in its sibling aggregate while other bundled
leaves remain available.
