# A log predicate must be declared in its source

The label method calls `needsAttention` in a guard without defining or importing
that word. Lexical validation must catch it even though the method is unused.
A later caller cannot supply a missing source declaration.
