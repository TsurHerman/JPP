# A log viewer routes incoming messages

The viewer sends errors and warnings to an operator, and stores informational
and debug messages in history. Each received record has a native Zig log level.

Read these files in order:

1. `log/model.jpp` names the native enum.
2. `log/routing.jpp` defines the boolean `needsAttention` predicate using the
   ordinary variadic `isOneOf` library function, then classifies the destination.
3. `log/labels.jpp` defines the display label, panel and icon.
4. `main.jpp` checks every runtime level and counts received records.

| Level | Label | Panel | Icon |
|---|---|---|---|
| error | ATTENTION | ALERTS | ! |
| warning | ATTENTION | ALERTS | ? |
| info | NORMAL | HISTORY | . |
| debug | NORMAL | HISTORY | . |

The icon demonstrates three levels of specificity: an exact enum case, a
predicate-qualified method, then the broad typed default. The panel uses an
ordinary string comparison in its qualifier: `destination(level) == "operator"`.

`debug_console.jpp` is a separate caller context. Its policy makes debug messages
need attention, including when the predicate is called from inside `destination`.
`known_error.jpp` shows that a known enum case requires only its selected branch;
the predicate does not need definitions for unreachable cases.

The native `received.jpp` fixture models severity codes 0–3 and counts producer
calls. It is not a log parser or a language memory model. Guard evaluation must
not receive a record twice or inspect runtime state during compilation.

`enum_guard_missing` and `enum_guard_ambiguous` are the negative companions.
