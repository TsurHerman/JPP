# cycle_ambiguity

A cycle does not create ambiguity between methods authored in different modules.
Local methods precede imports when specificity leaves equal or incomparable
maxima. Entering through `a` selects its crossing method; entering through `b`
selects the other. Importing both members keeps the first entry's order and does
not duplicate candidates. `a` deliberately imports `c` before `b`, contrary to
alphabetical order, to check authored precedence deeper in the cycle.

More-specific imported methods still win. Nested calls preserve the caller's
entry order, and a local caller override reaches both members. The separate
`cycle_local_ambiguity` case still rejects competing maxima in one source module.
