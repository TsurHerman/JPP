# cycle_facade_ambiguity

A facade authors one crossing method while a cyclic sibling authors the other.
A caller sees the facade through an outer folder and also explicitly imports
the sibling. The facade's local method takes precedence over its imported
sibling. Reversing those imports gives the sibling precedence. Neither the
cycle nor the outer folder erases this order, and repeated views of an authored
method do not create duplicate candidates.
