# A package cannot make one name both a value and a function

One file exports the constant `OffsetWidth = uint32`. Another exports a method
`OffsetWidth(::type) = uint64`. Importing their folder must diagnose the
value/method collision rather than hide one declaration behind the other.

This preserves an ordinary distinction: reading an existing width and calling
a function that computes a width require different definitions today.
