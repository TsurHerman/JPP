# Reading a file header: one byte, or a named failure

A binary reader returns a byte on success. It can also report that the input
ended or that the device failed. The application needs a clear message for each
outcome. The reader's actual Zig types are reused, not copied into new enums.

Start with [reader.jpp](reader.jpp):

```jpp
ReadError = Zig.std.Io.Reader.Error

explainRead(::uint8) = "Read one byte"
explainRead(ReadError.EndOfStream) = "The input ended before a byte arrived"
explainRead(ReadError.ReadFailed) = "The device could not read the byte"
```

`explainRead(readByte(bytes))` injects the success/error decisions before ordinary
method selection. Every possible runtime outcome must have one winning method.
The success method receives the byte; an error method receives the native error.
The read itself happens once. The machinery does not return early on a failure:
returning an error, producing a message, or applying a caller policy is explicit.

[main.jpp](main.jpp) covers the three outcomes, a broad error-set default, a
smaller error-set group, a boolean predicate qualifier, known selected-only
branches, and named/rest forwarding. `EndOfStream` from another error set is the
same native error; enum cases, in contrast, retain their owning enum's identity.
A static error narrows even when its source field was typed `anyerror`.

[retry_ui.jpp](retry_ui.jpp) starts a fresh caller context. Its policy replaces
only the device-failure message; successful reads and end-of-input messages keep
the library's implementations.

[validated.jpp](validated.jpp) checks a real composition: the file must begin with
`A`. Validation adds `InvalidMagic` while explicitly preserving read failures.
A variadic `isOneOf` predicate groups missing input and invalid magic into the
user action "Choose another file"; the device error keeps the reconnect default.
The resulting type is native `(ReadError || error{InvalidMagic})!u8`. Returning
successes and errors from different injected arms rejoins compatible native error
sets/unions; unrelated successful result types still error.

The fixture owns the byte source, intentional static fields and evaluation
counter. These are test support, not a new collection or memory model.

Run:

```sh
zig run src/jppc.zig -- tests/error_dispatch tests/.gen/error_dispatch
zig run tests/.gen/error_dispatch/run.zig
```
