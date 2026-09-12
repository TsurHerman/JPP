# base_shadow

A source-tree `Base.jpp` replaces the bundled library's root interface for
`using Base`. Both application and library explicitly import that name.
This is cross-root replacement, distinct from the rejected same-source
file/folder collision. `Base.Test` remains directly addressable even though
the source root exposes only its replacement arithmetic.
