# Failure cases do not become types in the authored order

`ReadError.EndOfStream` and `ReadError.ReadFailed` are native error values. The
`<:` order word still accepts only type values. Group failures with a predicate
or an explicit native error set; do not author type-order facts about individual
error values.
