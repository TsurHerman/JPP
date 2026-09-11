# any_override

Any is resolved through ordinary caller-first predicate dispatch. The
library imports Base's definition; its callers need not import it. With
the default definition, the Any-gated method beats the unconstrained type
binder for both integers and floats. A caller-supplied predicate with the
same name restricts membership to integers, so floats use the generic
method. A compiler wildcard would incorrectly keep accepting floats.
