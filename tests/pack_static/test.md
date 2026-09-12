# Static fields

Explicit native comptime fields (including integer dimensions) survive projection,
tuple/record construction, ordinary identity calls, and named forwarding. Runtime
data stays runtime. A call returning a static field still executes preceding
runtime effects; retaining a static result must not delete the call's effects.
Brace applications and general static arithmetic remain a later feature.
