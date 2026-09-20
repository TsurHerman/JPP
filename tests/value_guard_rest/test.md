# A whole rest pack is not one fixed guard coordinate

This guard examines a variadic pack as a whole. Its applicability can depend on
shape and several values, so it cannot be ranked as a unary value refinement.
The frontend rejects it explicitly; ordinary varargs calls inside a unary
predicate are supported by the log_labels example.
