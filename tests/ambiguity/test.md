# ambiguity (negative)

**Validates (README §4, §9):** two maximally specific methods in ONE
module = comptime error at the call — julia's venue (ambiguity is
harmless until a call hits it), jpp's timing (compile, not runtime).
`g(x::int64, y)` and `g(x, y::int64)` cross; `g(1, 2)` matches both;
neither dominates pointwise. The error names the cure: define the
intersection method. `expect.err` greps `call of 'g' is AMBIGUOUS`;
compile SUCCESS fails the case.
