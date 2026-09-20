# The caller cannot invent a library dependency

`provider.probe(x)` calls `tag(x)` without defining, importing or exporting `tag` in
provider.jpp. The application defines its own tag, but that does not repair the
library source. Compilation must identify the undeclared call in `provider.probe`.
Adding `export tag` to the library would explicitly declare the requirement.
