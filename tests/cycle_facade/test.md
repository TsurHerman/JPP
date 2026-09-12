# cycle_facade

A sibling importing its package forms a unit with the facade and wildcard.
The facade still exposes only its authored public interface; a selected
method can call other public unit words internally.

A second root explicitly imports both facade and worker: their overlapping
methods are deduplicated, and the explicit member import exposes the unit.
