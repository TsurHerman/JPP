# The UI forgot a device failure

A byte reader can produce `EndOfStream` or `ReadFailed`. This example explains
only end of input. Its sample happens to return `EndOfStream`, but the input type
still allows `ReadFailed` at runtime. Compilation must name that uncovered case.

Repair the table by adding:

```jpp
explain(ReadError.ReadFailed) = "The device could not read the byte"
```

An explicitly known `explain(ReadError.EndOfStream)` would need only that case.
