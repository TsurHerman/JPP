# One double function, two numeric domains

`algebra.double(x)` calls ordinary addition: `x + x`. The algebra module imports
`Base.Arithmetic`, so its dependency is declared in its own source. The caller
also imports integer and float providers ahead of that module's imports.

The same function returns 42 for 21 and 3.0 for 1.5. These providers agree with
Base; [base_import](../base_import/test.md) and [depth_override](../depth_override/test.md)
use deliberately different results to prove which provider wins.

Every import is explicit. Caller context chooses implementations of declared
words; it cannot repair a missing declaration in the library.
