# Grouping an integer does not make it a record

`(1)` is the integer 1 in parentheses. It has no field `a`, so `(1).a` must fail
with the tuple-or-record projection diagnostic. `(1,)` would instead be a
one-element tuple.
