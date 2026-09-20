# A type alias and method cannot replace each other

The module first binds `OffsetWidth = uint32`, then defines
`OffsetWidth() = uint64`. One local name cannot simultaneously denote that
constant and a method table. The frontend rejects the collision even though
`main` only reads the name.
