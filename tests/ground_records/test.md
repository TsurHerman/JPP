# ground_records

Ground return inference must distinguish runtime parameters from explicit
comptime fields. A record literal built from a runtime input must store
that input at runtime, including when another ground wraps and unwraps it.
The record's type-valued field must retain its actual type identity, and
explicit constant fields must keep their values. Different input values
of the same type must not create distinct inferred record types.
A ground may also select between records using a runtime Boolean; inference
must analyze the branch's type without trying to evaluate its condition.

The checkout example exposed the old mirror's bug: evaluating a ground
against an undefined comptime sample made ordinary record fields comptime,
so its real runtime return could not inhabit the inferred result type.
