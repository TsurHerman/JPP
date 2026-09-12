# folder_modules

Folders without a facade recursively expose their children's exported words.
A customary `folder/folder.jpp` facade controls `using folder`; its explicit
`using folder.*` imports siblings and subfolder interfaces while excluding
itself. Here `governed` republishes only `best`, while `governed.*` also exposes
`raw`. The facade and all leaves remain directly addressable by dotted paths.

Two programs check recursive imports, wildcard imports, facade reexports,
explicit dotted addressing, and a nested method's private declaration home.
Children are merged in alphabetical module-name order. `folder_collision`
rejects a same-source file and folder owning one identity; cross-root exact
replacement remains available (`base_shadow`). `facade_hidden` checks the
facade's controlled export boundary.
