# varargs_type_pack_witness

A rest of type values is still a tuple of values. Its name cannot witness a single where-bound type, unlike a fixed `T::type` input. Reject the declaration rather than treating the captured tuple's type as T or silently accepting an unused unbound constraint.
