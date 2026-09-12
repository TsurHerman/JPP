# wildcard_excludes_facade

`using box.*` gathers sibling files and subfolder interfaces while excluding
`box/box.jpp`. A definition authored only in that facade cannot be called via
the wildcard; importing `box` or `box.box` would expose its selected interface.
