# Comparing two account numbers needs a broader guard model

The proposed rule identifies a transfer whose source and destination account
numbers are equal. `sourceAccount::int64` binds an integer value and annotates
its type. Passing `sourceAccount` to a predicate does not pass `int64` instead.
Accounts 101 and 202 have identical types but different values.

This case has no enums. It pins the current frontend's single-input guard limit:
the declaration is rejected with `ValueGuardNeedsOneInput` even though main does
not call it. This is an implementation boundary, not a ratified prohibition on
relations between arguments. Runtime value relations also need a future branch
mechanism. Separate comma-separated guards on separate inputs already work.

A predicate on `typeof(sourceAccount)` and `typeof(destinationAccount)` would
instead compare types, which are both known to be int64. Likewise, a signature
with `sourceAccount::T` and `destinationAccount::S` can expose those types as T
and S. General calls such as `where sameType(T, S)` are not implemented yet;
they must not be confused with comparisons of the account numbers themselves.
The existing `type_bindings` case verifies the distinction between values and
their types. `where T == S` is a separate implemented authored-order relation,
not a substitute for arbitrary type predicates.
