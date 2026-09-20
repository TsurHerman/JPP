# A misspelled device failure cannot create a native error

An unused retry rule writes `ReadFaild` instead of `ReadFailed`:

```jpp
retry(problem::ReadError) where problem == ReadError.ReadFaild = true
```

The real `std.Io.Reader.Error` set is imported through `Base.Zig`. Its members
must already exist; the compiler cannot manufacture a new native error from a
typo. Compilation reports `no static member 'ReadFaild'` without calling the
method or running any reader operation.
