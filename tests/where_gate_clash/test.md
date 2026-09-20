# Overlapping predicates need an authored priority

Both `Integer` and `Signed` accept int64. The two `category` methods each
require one of these predicates, and `category(1)` matches both. Neither
constraint is declared more specific than the other.

Both methods belong to the same module, so import position cannot choose
between them. Compilation must report `call of 'category' is AMBIGUOUS`.
The compiler does not inspect predicate bodies to prove containment.

Adding `<:(Signed, Integer) = true` supplies the missing priority. The positive
[order_injection](../order_injection/test.md) case demonstrates that repair.
This test intentionally omits it, preserving the ambiguity diagnostic.
