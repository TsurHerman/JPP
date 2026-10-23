# Callable structs preserve their meaning

`F(args) do x, y { body }` constructs one anonymous callable and places it in
argument one. The receiver supplies the values, while the callback retains its
creation context and lexical home. `main` supplies a caller policy used only by
a closure constructed several calls deep. `isolation` deliberately imports a
receiver with a more-specific policy only after construction; that policy must
not change either the callback or an explicitly bound word.

The programs also cover one body instantiated at several types, captured type
identity, independent runtime captures with shared representation, private helper
visibility, nested and returned closures, callback scope, first-class projection
and chained application, named/rest packs, ordinary Function membership, delayed
effects, and evaluation exactly once in source order. They do not claim ownership
or lifetime checking for captured native pointers.
