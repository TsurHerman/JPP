# Error handling also needs the successful path

The UI explains every failure of a native `ReadError!u8`, but it forgot what to
do with a successfully read byte. Injected dispatch checks success as well as all
errors. Compilation must fail rather than treating the success as an error or
silently returning it to the caller.

Repair the table with an ordinary payload method:

```jpp
explain(::uint8) = "Read one byte"
```
