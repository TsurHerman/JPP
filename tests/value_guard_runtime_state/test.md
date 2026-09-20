# A runtime alert setting cannot decide a compile-time table

A log viewer can change `warning_alerts` while running. Its author tries to use
that mutable setting inside a dispatch qualifier:

```jpp
label(level::Level) where needsAttention(level) = "ATTENTION"
label(::Level) = "NORMAL"
```

`needsAttention` reaches a native predicate that reads the setting. Even the
known `Level.warn` case cannot tell the compiler what that runtime setting will
be later.

**Expected:** Zig rejects the ground with `unable to resolve comptime value`
when it reaches `Settings.warning_alerts`. The guard must not freeze the
setting's initializer into the generated table. A compile-time configuration
value or an ordinary runtime decision in the method body would be different
contracts.
