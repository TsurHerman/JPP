# Automatic variant dispatch

Ordinary calls inject a switch for tagged unions. Selected arguments are
Variant(owner, tag) values with a runtime .payload. Ordinary predicates group
variants and authored pairwise order refines the groups. Forwarding preserves
variants through rest and named packs. Explicit static union fields require
only the selected arm and may return a type. A producer with effects runs once.
