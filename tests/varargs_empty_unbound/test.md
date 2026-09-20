# varargs_empty_unbound

An empty uniform `values::T...` cannot infer T. With no fixed input or named witness supplying T, the candidate does not match. The compiler must not invent an element type for an empty tuple.
