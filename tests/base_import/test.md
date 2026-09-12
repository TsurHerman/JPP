# base_import

Every module authors the imports it needs. The Base folder supplies wrapping
int64 arithmetic, float64 arithmetic, floating `/`, and truncating integer
`div`; the compiler gives those words no bodies.

Three fresh contexts compare ordinary Base arithmetic, a caller override
placed before Base, and Base placed before the override. Import position
and caller-first accumulation determine which methods win. An inherited
Base entry also precedes a deeper library's own imports. Base has no special
fallback tier.
