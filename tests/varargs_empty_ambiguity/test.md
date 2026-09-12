# varargs_empty_ambiguity

An int64 rest and a float64 rest both accept zero elements. No supplied element witnesses either constraint, and both accept the same structural shape. Their call is ambiguous in one module; definition order must not choose a winner.
