# Identical text fields do not make two unions interchangeable

`owner()` and `other()` each declare a native tagged union with one `text`
field. Their shapes and payload types agree, but they are different types.
`Owned` accepts only variants of the first declaration; the call deliberately
passes a value from the second.

Compilation must fail to find a method. A field name is not permission to
impersonate a different union's variant.
