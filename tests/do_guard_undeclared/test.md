# Callable operands retain lexical checks inside unused value guards

An unused method's guard binds a word that has never been declared. Recursive
lexical requirements include word captures and nested callback bodies in guard
expressions as well as ordinary method bodies. The declaration must fail even
though guard evaluation and method selection never occur.
