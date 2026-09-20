# A named comparison still depends on two inputs

A binary converter proposes a rule for equal source and destination layouts:

```jpp
conversion(Source::type, Destination::type)
    where ==(; left = Source, right = Destination) = "bit copy"
```

That named `==` call is an ordinary predicate with two independent inputs. This
increment supports value qualifiers over one fixed input, so the frontend must
reject it with `ValueGuardNeedsOneInput`.

It must not drop the argument names and reinterpret the call as the existing
`where Source == Destination` type relation. That relation has its own authored
order semantics; preserving the written call prevents an accidental change in
meaning.
