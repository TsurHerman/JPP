# varargs_type_mismatch

An explicit named type witness must agree with every element of a uniform positional rest. Passing int64 data with T = float64 is a no-match; the binder performs no conversion.
