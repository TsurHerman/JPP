# Reading a field that the record does not have

The record `(; a = 1)` contains only `a`; projecting `.b` must fail compilation with
`no field 'b'`. A missing field is not a new variable or an optional value.
