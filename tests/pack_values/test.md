# Pack values

`()`, `(x,)`, heterogeneous tuples and `(; name = value)` records are values.
Positionals retain order; named field identity is independent of spelling order.
Mixed positional/named packs use the same two sections as calls. `.0` and `.name`
project fields; the ordinary Tuple library supplies len, first and tail.
Producers execute once in written order before field canonicalization. Ordinary
data does not specialize the pack; static type fields do. Empty is not nothing.
