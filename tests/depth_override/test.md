# depth_override

**Validates (README §1, §10.5):** overrides are surgical and reach
through any depth — BY CONTRAST. Two programs run the SAME calls:
`plain` (no override: report(21)=42, square(21)=441) and `shadowed`
(tweaked `+` leads: report(21)=1000). The sentinel 1000 cannot arise
from any real addition of the probes, so its appearance proves the
override rode the context through `stats` and `algebra` — two
modules that never imported it. `*` has no override: square is
identical in both worlds.
