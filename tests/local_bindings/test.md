# local_bindings

Inside a body block, `name = expression` names a value once. The normalizer
aliases its value reference; it emits no assignment operation and never
repeats the producing call. Bindings may hold literals, runtime records,
parameters, or actual type values. `_ = expression` discards a result while
preserving its effects and may be repeated.

Bindings are sequential and immutable within a method. Blocks group
expressions without introducing another binding scope; their value is the
last expression, including when that expression is a binding. An explicit
local binding can shadow a module word as a value. Calling local values is
not implemented and must not silently call the same-spelled module word.

Negative sibling cases pin rebinding, use before definition, and unsupported
local calls. Unlike compiler diagnostics, these are detected by the frontend
and use `expect.transpile.err`.
