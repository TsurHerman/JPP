# Choose an encoding for a binary word type

A binary writer supports unsigned 32-bit and 64-bit words. Other types need a
separate encoding implementation:

```jpp
encoding(T::type) where supportsWord(; valueType = T) = "little-endian word"
encoding(::type) = "unsupported"
```

`supportsWord` takes one **named** argument, `valueType`. The qualifier must keep
that name when it calls the predicate. The compiler must not silently turn the
call into `supportsWord(T)`, which would supply a positional argument to a named
input.

Both supported word types select the guarded method. Signed integers and floats
select the default. All four inputs are ordinary compile-time type values.
The existing positional type-gate syntax, such as `where Integer(T)`, retains
its separate meaning.
