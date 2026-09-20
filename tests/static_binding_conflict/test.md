# Two offset widths cannot share one package constant

One package file exports `OffsetWidth = uint32`; another exports
`OffsetWidth = uint64`. Importing the package would expose two different values
under one name. Compilation must diagnose `conflicting exported values`.

Constants do not form a method table. The package author must choose its public
width or give the two widths different names. Identical exported constants may
coalesce; `static_bindings` checks that separate valid case.
