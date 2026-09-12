# base_missing

A source-tree `Base.jpp` replaces the library root and exports a declaration
of `+` without implementing it. The application's explicit `using Base`
makes the call lexically valid, but dispatch must reject it with no matching
method. Neither bundled arithmetic nor a hidden compiler implementation may
fill the missing definition.
