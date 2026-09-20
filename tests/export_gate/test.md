# A module cannot call another module's private helper

`secret.jpp` defines `hidden(::int64) = 42` without exporting it. Importing
`secret` must not make that helper available to `main.jpp`.

The attempted `hidden(7)` call must fail compilation. The private definition
has a file-local identity, so an outside call cannot resolve to it. This test
keeps the diagnostic promise in `expect.err`; a successful compilation is a
regression, regardless of the private method's result.
