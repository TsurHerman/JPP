# A losing candidate can still decide the winner

All three predicates A, B and C accept the sample type. The only authored
priorities are `A <: B` and `B <: C`; no direct `A <: C` edge exists.

With all three methods present, B eliminates C and A eliminates B, leaving A
as the sole winner. If context collapse deletes B just because it loses to A,
the remaining A and C methods become incomparable. That changes the result.

The call must return A's marker, 1. These intentionally abstract names expose
the graph being tested; their numbers identify methods, not application data.
The regression protects a decision dependency, not transitive closure.
