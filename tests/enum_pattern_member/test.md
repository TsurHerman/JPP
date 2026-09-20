# A misspelled warning case is not a variable

A log viewer writes `label(Level.warning)`, but Zig's log enum declares `warn`.
The qualified name must look up a real case; it cannot bind a new input or
create a case called `warning`.

`main()` never calls `label`. Compilation must still report
`no static member 'warning'` while checking the declaration. Correcting the
signature to `Level.warn` fixes this typo.
