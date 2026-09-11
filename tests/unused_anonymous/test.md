# unused_anonymous

An unused unannotated slot is not rescued by replacing its name with `_`.
Use `::Any` to explicitly accept every input, or a narrower annotation.
The declaration must fail even when it is not called. Named and anonymous
inputs therefore share the same annotation rule.
