# any

`::Any` explicitly accepts every input domain. It preserves the concrete
bound value and type, including type values, and has the same specificity
as a used unannotated binder. Exact and predicate constraints still beat
it; equal specificity still follows context position.

Named `x::Any` and anonymous `::Any` may both be unused, including in
grounds. An `::Any` result permits the inferred concrete result, also
through a bound type-valued return annotation. `Any` in value position is
that particular type value, not a wildcard. Universal input acceptance
does not implicitly author `<:` facts: that relation remains pairwise.
