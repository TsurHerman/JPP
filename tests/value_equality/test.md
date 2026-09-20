# Compare log labels and native case identities

`==` is an ordinary exported Base word. Strings compare by contents, scalar
values compare within the same type, enum values retain owner identity, and
native errors retain their shared identity across error sets. Equality does not
introduce mixed numeric promotion, collection equality or record equality.

The ordinary variadic `isOneOf(value, cases...)` predicate uses those same
methods. Its empty form is false; a listed matching case is true. This is a
membership query over a statically shaped pack, not a first-class predicate
factory or a runtime collection traversal API.
