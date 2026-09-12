# any

`using Base.Any` imports an ordinary predicate from `Base/Any.jpp`:
`Any(::type)::bool = true`. It is callable like any other word and has a
class identity when passed as a value. `<:Any` preserves the concrete
bound value and type, including type values, and has the ordinary
predicate rank. It beats an unconstrained binder even from a later module;
exact input types still beat it.

Named `x<:Any` and anonymous `<:Any` may both be unused, including in
grounds. Results use ordinary inference or concrete return annotations;
there is no special Any return type.

Base also authors `<:(::type, Any) = true`, making other predicate gates
preferred to Any. This is an ordinary order method, not a compiler floor:
`any_order_gap` and `any_shadow` prove it disappears when that module is
absent or replaced. `any_override` proves membership is caller-selected;
`any_unimported` proves the name is not a builtin.
