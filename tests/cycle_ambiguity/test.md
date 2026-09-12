# cycle_ambiguity

Crossing methods authored in mutually importing files compete inside one public
dispatch unit. Calling their overlap must be ambiguous; import position cannot
choose a file within that unit. Acyclic modules retain ordinary position ties.
