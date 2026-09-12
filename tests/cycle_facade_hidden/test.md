# cycle_facade_hidden

A facade filters the package API even when sibling imports put it in an SCC.
A caller importing only the package cannot name an omitted sibling export.
