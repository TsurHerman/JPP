# A keyword needs a name

`shippingCost(; ::int64)` gives its keyword input a type but no name. A caller could
not address that field. The frontend rejects it with `NamedInputNeedsName`; write a
name such as `grams::int64`.
