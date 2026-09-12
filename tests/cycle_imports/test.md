# cycle_imports

A three-file strongly connected import component is one public dispatch unit.
Importing any member exposes its public declarations, and importing multiple
members does not duplicate methods. Original source files remain lexical homes:
both private helpers have the same source spelling and retain distinct bodies.
Two fresh roots verify caller-first overrides and isolation between programs.
The bodies form an acyclic call path; this case does not promise recursive
runtime execution or recursive return-type inference.
