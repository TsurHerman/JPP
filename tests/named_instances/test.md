# Bound instance identity

Observe the actual bound pack type and state whose native type explicitly depends
on that pack. Keyword permutation and different runtime data reuse the pack;
a different static type value changes it. This carries binder convergence into
the surface without assuming that unrelated native static variables are isolated
per specialization.
