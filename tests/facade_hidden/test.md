# facade_hidden

The customary `box/box.jpp` facade imports its siblings and republishes only
`public`. Importing `box` does not expose sibling word `hidden`; the attempted
call fails lexical validation. Explicit `box.*` or `box.leaf` would expose it.
