# Arithmetic and explicit conversion

Status: same-type int64/float64 arithmetic RUNS in Base.Arithmetic. Promotion,
additional widths, and conversion policies remain future library work.

Arithmetic is ordinary code imported through Base or its Arithmetic leaf. Exact
int64 +, - and * wrap. Float64 operations use floating arithmetic. Division `/`
returns float64 for int64 and float64 pairs; `div` truncates integer division
toward zero. Mixed arithmetic without an imported promoting library still fails.

## The first wider library

Start with a finite table over int32/int64/float32/float64. Supply concrete grounds
per supported operation/type, ordinary predicates for Integer/Float/Real, explicit
pairwise promotion rules, and explicit conversion methods. Predicate membership,
dispatch preference, promotion, and conversion are separate relations.

A mixed binary operation chooses a common type, converts both inputs, and invokes
the exact operation. Test that this reaches a concrete ground or reports the
unsupported pair. Do not hide conversions in binding or use a variadic fallback
that repeats the same binary call.

The current ledger requires exact convert: lossy conversion is an error. The old
sketches' unchecked @floatCast and @floatFromInt are not an implementation of
that promise. Before implementing the matrix, specify integer range failures,
floating precision loss, non-finite inputs, and signed zero. Calling something
Julia-oriented cannot substitute for an explicit table of accepted values.
A changed conversion policy requires an explicit ledger decision.

## Failure stages are part of the interface

Missing type-pair rules and ambiguous implementations fail at compilation.
A supported conversion of runtime data can fail during execution. Add a harness
for expected runtime failures before claiming conversion coverage; expect.err
only checks compilation and cannot prove runtime checks exist.

Check result types and values in two caller contexts. Callers may override
promotion through deep generic libraries; return inference must follow that
same decision. Document reduction order because arbitrary authored promotion
rules need not be associative. Measure specialization cost at growing arities.

Signed/unsigned tables, checked arithmetic policies, target intrinsics, and
larger numeric families follow after this matrix. Machine target selection needs
explicit declared tags and concrete fallback grounds; no undeclared ARCH or
unsafe placeholder C implementation belongs in the baseline example.
