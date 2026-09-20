# A log viewer forgot warnings

A log viewer displays a label beside each incoming message. It uses Zig's
existing log-level enum, which has four cases: `err`, `warn`, `info`, and `debug`.

The definitions in [main.jpp](main.jpp) accidentally cover only three:

```jpp
using Base.Zig

Level = Zig.std.log.Level

label(Level.err)   = "ERROR"
label(Level.info)  = "INFO"
label(Level.debug) = "DEBUG"
```

When a message arrives, the viewer makes an ordinary call:

```jpp
main() = {
    level = incomingLevel()
    label(level)
}
```

That call generates a switch over the possible levels. The three methods
provide three branches, but **what should a warning display?** There is no
matching method, so compilation fails. The diagnostic includes:

```text
Input 0 = log.Level.warn
```

`Input 0` means the first argument to `label`; `log.Level.warn` is the
unhandled native enum value. Add one ordinary method to complete the table:

```jpp
label(Level.warn) = "WARNING"
```

The completed table displays `ERROR`, `WARNING`, `INFO`, or `DEBUG`, according
to the incoming level. No explicit switch or fallback is needed in jpp.

## What this test promises

This is an **intentional compile failure**. The missing method stays missing
in the fixture so the test catches any compiler change that silently accepts
an incomplete runtime table.

`incomingLevel()` is a tiny native fixture returning an ordinary `Level` value;
it does not implement log input. Its sample is `.info`, but ordinary ground
returns are runtime data in jpp, so compilation still checks every possible
level. Optimizer knowledge of the sample does not relax that rule.

By contrast, `label(Level.info)` passes an explicitly known case and needs only
the `info` method. Exhaustiveness is required for a runtime enum argument,
not for every word that happens to have an enum method.
