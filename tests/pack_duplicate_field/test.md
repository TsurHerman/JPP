# A record cannot define the same field twice

`(; a = 1, a = 2)` tries to create two fields named `a`. The frontend reports
`DuplicateNamedArgument`; it must not choose either value or silently overwrite the
first.
