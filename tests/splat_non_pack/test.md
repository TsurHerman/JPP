# splat_non_pack

An integer is not a statically shaped tuple or named record. Splatting it must fail during pack expansion rather than silently wrapping it or treating the number as an arity.
