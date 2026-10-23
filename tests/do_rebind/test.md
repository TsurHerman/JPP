# Callback inputs remain immutable

The callback creates a lexical scope, and the ordinary sequential immutable
binding rule applies within it. A body cannot replace one of its inputs.
