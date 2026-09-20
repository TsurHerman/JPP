# Computing a module constant needs a staging rule

`chooseWidth()` returns `uint32`, but `OffsetWidth = chooseWidth()` still uses
an ordinary call in a module initializer. That form is deliberately rejected
until its evaluation stage and dispatch context have a general contract.

Writing `OffsetWidth = uint32` is supported. This negative case ensures the
compiler does not quietly invent different staging rules for convenient calls.
