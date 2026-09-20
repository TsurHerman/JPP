# An unused default still names an existing log level

The default log-level helper contains a typo:

```jpp
defaultLevel() = Level.wran
```

Only `warn` and `info` exist. Compilation reports `no static member 'wran'`, even
when the helper is unused. Ordinary bodies and qualifiers follow the same
lexical lookup rule for known module values.

This check inspects only the known value and member path. It does not execute
unused methods, native grounds or function calls. Runtime payload fields and
fields selected from call results stay deferred until their types are known.
