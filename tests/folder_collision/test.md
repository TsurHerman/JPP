# folder_collision

A source tree cannot contain both `thing.jpp` and a module-bearing `thing/`
folder: both would own `using thing`. This is a frontend module-identity
error. A customary child `thing/thing.jpp` is allowed: it is directly addressable as
`thing.thing` and supplies the folder facade. Cross-root source replacement
of bundled Base is separate.
