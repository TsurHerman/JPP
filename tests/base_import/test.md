# base_import

Modules receive an ordinary `Base` import after their explicit imports.
The library supplies wrapping int64 arithmetic, float64 arithmetic, floating
`/`, and truncating integer `div`. The compiler gives those words no bodies.

Three fresh contexts compare the default, a caller override that reaches
an imported library, and an explicit `using Base` placed before the override.
Explicit Base retains its written position and is not added again. Existing
specificity and caller-first accumulation rules apply to this import too.
In particular, an inherited Base entry precedes a later library's own
imports. Base is an ordinary import, not a specially demoted fallback tier.
