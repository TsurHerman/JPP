# order_injection

**Validates (README §4, §9):** injecting one order fact cures a
gated-vs-gated clash, in the same module that raised it.

This folder is `where_gate_clash` plus a single line. That case does not
compile: `Integer` and `Signed` overlap, `g(1)` matches both gated
methods, both sit at rank 2 because a gate lifts a binder to the
predicate rung, and rank alone cannot separate them. Add

```
<:(Signed, Integer) = true
```

and the narrower gate answers 2. Diff the two folders and the diff IS
the promise.

**Why "injection" and not "partial order".** jpp's `<:` is authored,
never proven. There is no transitive closure — chains are declared or
absent — and a mutual pair ties the two classes for that direct
comparison without inferring a transitive equivalence. So what a module injects is a set of edges, not an order with
laws the machinery will extend on its own. A missing edge is false
rather than a gap to be inferred.

**The order is a word, so injection is ordinary shadowing.** The fact is
a method on `<:`, its arguments are existing class values imported from `preds`, and a negative fact
is `= false`. A later module leading the context can therefore turn this
edge off by position, exactly like shadowing any other method.

The sibling `order_refines` case injects the edge from a SEPARATE module
and reverses it to flip the winner.
