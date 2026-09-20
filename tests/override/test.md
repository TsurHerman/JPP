# A caller changes a library's declared dependency

Two programs make the same calls with different imports:

| Program | Leading provider | Direct `tag(21)` | Library `probe(21)` |
|---|---|---:|---:|
| `plain.jpp` | `base` | 1 | 1 |
| `shadowed.jpp` | `loud` | 99 | 99 |

The numbers identify the provider that answered. Both providers have the same
signature; only their context positions differ.

`lib.jpp` declares `export probe, tag`. Its `probe(x) = tag(x)` therefore has a
valid local declaration for `tag`, with no invented fallback implementation.
The caller supplies the implementation and retains priority inside the library.
Neither an implicit import nor an undefined name is involved.
