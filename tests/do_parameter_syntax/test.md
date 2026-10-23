# Do parameters use a bare name list

Write `do x, y { ... }`; parenthesized parameters are not an alias. This leaves
tuple-pattern syntax unclaimed and prevents conflicting interpretations.
