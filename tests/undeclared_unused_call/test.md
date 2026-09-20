# An unused body still exposes a misspelled call

`unused(x) = typo(x)` refers to an undeclared word. `main()` never calls this
method, but compilation must identify `typo` in `main.unused`. Dead code does not
provide an escape from lexical validation.
