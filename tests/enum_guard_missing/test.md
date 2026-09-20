# The log viewer has no normal-message label

The predicate accepts errors and warnings. No method covers info or debug.
An incoming runtime level therefore makes compilation fail at the first missing
case, `Level.info`, even though the fixture's sample happens to be an error.
Adding `label(::Level) = "NORMAL"` supplies the missing behavior.
