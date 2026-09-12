# Checkout: a modular application case study

**RUNS.** Twenty source modules, two independent application contexts,
twenty baskets, and 161 assertions. This case tests whether useful domain
code remains understandable as modules call through other modules. The
policies are fictional; the arithmetic domain is bounded nonnegative integer
cents, quantities, and grams. This is a quote calculator, not a payment system.

From the repository root:

```sh
zig run src/jppc.zig -- tests/checkout tests/.gen/checkout
zig run tests/.gen/checkout/run.zig
```

`zig build test` includes the case. Start reading at
[checkout/checkout.jpp](checkout/checkout.jpp), then compare
[retail.jpp](retail.jpp) with [member.jpp](member.jpp).

## Module structure

```text
retail                         member
  │                              ├── policies.member
  └──────────────┬───────────────┘
                 checkout (facade: exports only quote)
                  ├── pricing.cart
                  │    └── pricing.lines
                  │         └── pricing.discounts
                  │              └── money → arithmetic.rounding → Base
                  ├── shipping (facade)
                  │    └── shipping.carrier
                  └── tax → money

model = aggregate of line, physical, digital, basket, priced, quote
arithmetic = aggregate of logic, rounding
Base = explicit foundation import; Base.Arithmetic selects only arithmetic
```

`Line` composes the ordinary structural predicates `Physical` and `Digital`,
defined in separate files with their own constructors and accessors. A basket
captures zero or more inputs, checking Line independently for each; its tuple
may contain different concrete record types. `priceBasket` splats that tuple
into a shrinking `priceLines` reduction with an explicit empty identity.
Pricing, discounts, rounding, delivery, and tax calculations remain jpp calls. Ground code supplies primitive
arithmetic, selection, record storage, and receipt printing.

One deep path is `quote → priceBasket → netLine → lineDiscount → rateAmount →
roundQuotient → div`. The member policy's
`discountRate` is selected inside `lineDiscount`, without passing a policy
argument through those libraries. Its `freeShippingThreshold` separately
changes delivery policy. Neither library imports the member application.

## Executable expectations

The default discount is 10% for a line containing at least ten units. The
member policy gives 5% below ten units and 15% from ten units. Discounts round
per line to the nearest cent, ties upward. Freight is 350 cents plus 75 cents
per started kilogram, waived when no physical weight remains, for an empty quote, or when discounted goods
reach the applicable threshold: 10,000 cents retail, 5,000 member. Fictional
tax is 20% of net goods plus freight, rounded once.

| Same input basket | Gross | Retail discount | Retail total | Member discount | Member total |
|---|---:|---:|---:|---:|---:|
| 2 × 1,299 cents at 250 g; 1 × 2,500 cents at 800 g | 5,098 | 0 | 6,718 | 255 | 6,412 |
| 10 × 1,299 cents at 250 g; 2 × 2,500 cents at 800 g | 17,990 | 1,299 | 20,029 | 2,199 | 18,949 |
| Both quantities zero | 0 | 0 | 0 | 0 | 0 |
| Zero lines | 0 | 0 | 0 | 0 | 0 |
| Two digital books at 499 cents | 998 | 0 | 1,198 | 50 | 1,138 |
| Physical 1,000; digital 2 × 500; physical 3 × 200 | 2,600 | 0 | 3,630 | 130 | 3,474 |

Additional cases pin exact and just-below freight and bulk thresholds,
discounts applied before the freight threshold, and per-line rounding
(two 5.5-cent discounts become 12 cents together, not 11). Each quote checks
all six fields plus `gross − discount = net` and
`net + freight + tax = total`. The two programs begin with fresh contexts.

## What is comfortable, and what is missing

| Observation from this code | Design implication |
|---|---|
| Arithmetic is defined once in Base.Arithmetic; consumers import Base or that leaf explicitly. | Arithmetic consumers state their Base dependency. Logic and rounding helpers remain explicit imports; consumers never need to re-export operators. |
| `using pricing.lines`, `using shipping`, and `using tax` explain domain dependencies. | Keep domain imports explicit. A same-name facade gives a folder a focused public API. |
| One policy import changes both discounts and freight deep in the same library graph. | Caller context is useful without policy parameters on every helper. Defaults have real meanings here. |
| `quote` now names prices, net goods, freight, tax, and total in one body; `netLine` and `priceBasket` also bind intermediate results. | Immutable bindings replace helpers used solely for carrying results. They alias existing ANF values, preserving evaluation once and in source order. |
| The quote constructor has six required named fields; construction and access use the surface. | Names make tax and freight distinguishable at the call site; only the underlying domain records still need grounds. |
| A basket can have zero, one, or many heterogeneous lines. | Rest capture and shrinking recursion keep per-line pricing in jpp dispatch; a whole-cart ground loop is unnecessary. |

The current direction is explicit foundation/domain imports and explicit exported
extension points. Base's facade selects its public interface. The export-only
tunnel and imported re-exports now run, and all calls are lexically checked.
Checkout has meaningful fallback policies; declaration_tunnel separately tests
an interface that requires a caller implementation.

Basket storage is an ordinary positional pack captured by `items<:Line...`.
The short predicate annotation admits different Line types; `items::T... where T`
would instead require one uniform type. The quote constructor is named-only and its
result is an ordinary structural record, with no handwritten Zig wrapper.

`choose` evaluates both value arguments before selection; it is not lazy
control flow. Counts, cents, and grams still share `int64`; input validation,
overflow policy, unit types, and runtime-sized collections remain outside this
example's tested domain.

The initial Base exports same-type int64/float64 arithmetic and int64 `div`.
Rounding uses `div` explicitly because ordinary `/` produces a floating
quotient. `Any` and its authored order are available through Base, or Base.Any explicitly. Base has
ordinary context position, including precedence over imports reached later;
it is not a special fallback tier. The member policy is imported ahead of it.

## Machinery failures this example exposed

- Context collapse discarded member overrides when their dependency was
  reachable only through deeper imports. Discovery now walks the static
  import graph and all candidate bodies/gates, retaining caller modules
  needed later. It does not bring deeper modules into resolution early.
  [collapse_imports](../collapse_imports/test.md) isolates both promises.
- Deep inference exhausted the existing comptime quota. Discovery uses a
  worklist, and context extension/canonicalization cache their computed
  values in generic declarations. The quota remains unchanged.
- Inferred grounds constructed records with accidentally comptime data
  fields. Inference now analyzes against runtime parameters while preserving
  explicit static fields. [ground_records](../ground_records/test.md) isolates
  this boundary, including type identity and runtime selection.
- A void ground ending in a semicolon emitted a second semicolon. Receipt
  printing exercises the corrected statement emission.
- Adding implicit Base exposed generated `Base`/`base` filename collisions
  on a case-insensitive filesystem. Escaped module filenames and aliases now
  preserve identity; [module_encoding](../module_encoding/test.md) covers
  case, punctuation, aggregation, and driver/runtime names.
