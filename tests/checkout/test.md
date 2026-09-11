# Checkout: a modular application case study

**RUNS.** Nineteen source modules, two independent application contexts,
thirteen baskets, and 105 assertions. This case tests whether useful domain
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
                 checkout (takeover: exports only quote)
                  ├── pricing.cart
                  │    └── pricing.lines
                  │         └── pricing.discounts
                  │              └── money → arithmetic.rounding
                  ├── shipping (takeover)
                  │    └── shipping.carrier
                  └── tax → money

model = aggregate of line, basket, priced, quote
arithmetic = aggregate of integers, logic, rounding
```

`Line` is an ordinary structural predicate over native record types. The
two-line basket binds one shared type and checks that predicate. Constructors
and accessors cross the Zig boundary; pricing, discounts, rounding, delivery,
and tax calculations remain jpp calls. Ground code supplies primitive
arithmetic, selection, record storage, and receipt printing.

One deep path is `quote → priceBasket → pricePair → netLine → deduct →
lineDiscount → rateAmount → roundQuotient → arithmetic`. The member policy's
`discountRate` is selected inside `lineDiscount`, without passing a policy
argument through those libraries. Its `freeShippingThreshold` separately
changes delivery policy. Neither library imports the member application.

## Executable expectations

The default discount is 10% for a line containing at least ten units. The
member policy gives 5% below ten units and 15% from ten units. Discounts round
per line to the nearest cent, ties upward. Freight is 350 cents plus 75 cents
per started kilogram, waived for an empty quote or when discounted goods
reach the applicable threshold: 10,000 cents retail, 5,000 member. Fictional
tax is 20% of net goods plus freight, rounded once.

| Same input basket | Gross | Retail discount | Retail total | Member discount | Member total |
|---|---:|---:|---:|---:|---:|
| 2 × 1,299 cents at 250 g; 1 × 2,500 cents at 800 g | 5,098 | 0 | 6,718 | 255 | 6,412 |
| 10 × 1,299 cents at 250 g; 2 × 2,500 cents at 800 g | 17,990 | 1,299 | 20,029 | 2,199 | 18,949 |
| Both quantities zero | 0 | 0 | 0 | 0 | 0 |

Additional cases pin exact and just-below freight and bulk thresholds,
discounts applied before the freight threshold, and per-line rounding
(two 5.5-cent discounts become 12 cents together, not 11). Each quote checks
all six fields plus `gross − discount = net` and
`net + freight + tax = total`. The two programs begin with fresh contexts.

## What is comfortable, and what is missing

| Observation from this code | Design implication |
|---|---|
| Arithmetic is defined and exported once; ten consumers repeat `using arithmetic`. | A small implicit foundation import could remove repetition. Operators and `Any` should remain ordinary library definitions. Consumers need not export operators. |
| `using pricing.lines`, `using shipping`, and `using tax` explain domain dependencies. | Keep domain imports explicit. A takeover module gives a folder a focused public API. |
| One policy import changes both discounts and freight deep in the same library graph. | Caller context is useful without policy parameters on every helper. Defaults have real meanings here. |
| `withPrices`, `withShipping`, `withTax`, and `deduct` mainly carry intermediate results. | Implement the ratified immutable local bindings (§6): names for dataflow edges, not mutable state. |
| Record creation and access require grounds; the quote constructor takes six integers in order. | Record surface syntax and the already-validated named-pack binder would make inputs and units easier to inspect. |
| The basket is fixed at two lines. | Variadic packs or traversal are needed before claiming a general cart. Putting its entire loop in a ground would bypass jpp dispatch and weaken the experiment. |

The preferred direction is **a small implicit foundation, explicit domain
imports, and explicit exported extension points**. The implicit import and
export-without-body tunnel remain proposals, not features implemented by
this case. All calls here have actual source-visible local or imported
definitions. Meaningful defaults suffice for these policies; a future case
with a service that genuinely requires a provider should test the tunnel.

`choose` evaluates both value arguments before selection; it is not lazy
control flow. Counts, cents, and grams still share `int64`; input validation,
overflow policy, unit types, and arbitrary basket sizes remain outside this
example's tested domain.

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
