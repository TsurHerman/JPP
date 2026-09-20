# A misspelled log level is not a new case

An unused label method contains a typo:

```jpp
label(level::Level) where level == Level.wran = "ATTENTION"
```

`Level` defines `warn` and `info`; it does not define `wran`. Compilation must
report `no static member 'wran'`, even though `main` never calls `label`.

The qualifier's module-member path is a lookup, not a variable declaration.
Checking it does not evaluate the predicate or require a sample log message.
