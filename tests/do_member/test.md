# Known captures keep lexical member validation

A dormant callback captures a known module-derived enum type. Its misspelled
member must fail before invocation, just like a known module path in an ordinary
unused body. Unknown callback inputs remain subject to instantiation instead.
