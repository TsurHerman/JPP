# Select a sensor's build-time configuration

A sensor samples either slowly or quickly, and is deployed in a room or a hot
cabinet. These settings are module constants: their values are available when
the program is compiled.

| Setting | Selected implementation |
|---|---|
| 5 samples per second | Polling |
| 100 samples per second | Interrupts |
| 18.0 degrees Celsius | Passive cooling |
| 42.5 degrees Celsius | Fan cooling |

Ordinary predicates apply integer and float thresholds to known values. A true
guard selects the specialized method; a false guard leaves the typed default.
No runtime numeric switch is needed. This exercises the same guard evaluation
used for a known enum case, without requiring an enum or tagged union.

It does not implement runtime interval dispatch. An ordinary body literal or a
runtime temperature reading is still data: `value_guard_runtime` checks that an
unknown value cannot silently become a compile-time fact.
