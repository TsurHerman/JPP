# A singleton tuple has only position zero

`(1,)` contains one element at `.0`. Projecting `.1` must fail compilation with `no
field '1'`, rather than read past the tuple or return a placeholder.
