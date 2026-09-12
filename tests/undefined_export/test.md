# An export declares, but does not implement

`claims` exports Missing without a body. That creates a usable word identity,
not a candidate. Calling it with no implementation must still fail. This replaces
the previous rejection of all declaration-only exports after the tunnel decision.
