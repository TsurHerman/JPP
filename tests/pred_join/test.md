# pred_join

**Validates (README §4):** a predicate can be DEFINED from other
predicates, so `where` never needs boolean combinators of its own. And
`||` / `&&` are ordinary overridable words, not builtins.

```
Integer(T::type)::bool     = Signed(T) || Unsigned(T)      # a join
SmallSigned(T::type)::bool = Signed(T) && Small(T)         # a meet
```

**Why `where T <: Upper || T <: Lower` is not a notation gap.** The
answer to a disjunction is to NAME the class: define `Triangular(T) =
Upper(T) || Lower(T)` and gate on it. That keeps `where` a flat list of
predicates and keeps every class a thing with a name that `<:` can talk
about. An anonymous disjunction inside a gate could not appear in the
order at all.

**The operators are words.** `a || b` parses to a call of the word
`||`, exactly as `a + b` already parsed to a call of `+`. Both are
defined here in `preds.jpp` over `bool`, exported, and shadowable by
position like anything else. The transpiler contributes only lexing and
precedence — loosest first: `|| < && < + - < * /`. The `Prec` predicate
pins that: `Signed(T) && Unsigned(T) || Unsigned(T)` is true on every
unsigned type under the correct reading and false under the other, so
`pkind(ubyte())` answering 1 is the precedence itself under test.

**The edges are DECLARED, and that is the point.** Anything answering
`Signed` answers `Integer` — forced by the definition of `Integer`, and
obvious by inspection. `order.jpp` states the edge anyway. This is not
a missing prover.

Containment is not what the order is for. Most edges worth writing are
edges containment cannot reach:

- INCOMPARABLE pairs — `Wide` and `Signed` overlap with neither
  containing the other, so no analysis yields an edge and the author
  simply picks one (`tests/order_refines`).
- TOWER pairs — README §9 ratifies `Int <: Float`, "ints sit below
  floats", between classes that are DISJOINT. Containment says nothing
  about disjoint classes, yet this is the edge promotion runs on.

Containment-derivable edges like `Signed <: Integer` are the easy
minority, and writing them costs one line.

Two more things fall out of declaring rather than deriving. A derived
edge could not be supplied by a CALLER, which is the whole of
`tests/lattice_bridge` and `tests/order_injection`. And a predicate
whose body is opaque ground (`zig{}`, and most are) admits no proof at
all, so a prover would silently cover some classes and not others.

**Scope found while writing this.** A body may only reference
PARAMETERS, so the natural value-to-type delegation

```
Signed(a::T)::bool where T = Signed(T)     # rejected: `T` is not a param
```

does not normalize — a `where`-bound type variable is not in scope in
the body. Predicates therefore take their subject as `T::type` and are
asked about types only.
