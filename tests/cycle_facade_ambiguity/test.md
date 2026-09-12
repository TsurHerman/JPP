# cycle_facade_ambiguity

A facade authors one crossing method while a cyclic sibling authors the other.
A caller sees the facade through an outer folder and also explicitly imports
the sibling. Both methods still belong to the same dispatch unit: neither the
facade view nor the outer folder may turn their overlap into a position tie.
