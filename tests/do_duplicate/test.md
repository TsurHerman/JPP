# Callback inputs have distinct names

A do block has one lexical input environment. Duplicate fresh input names are a
compilation error instead of becoming accidental equality constraints. Existing
exact value patterns can repeat, as in ordinary method signatures (`do_types`).
