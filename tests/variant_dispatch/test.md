# Shipping quotes from a tagged shipment

A shipment stores its base price in cents. Standard delivery uses that price;
express delivery adds a 100-cent surcharge. The behavior is ordinary jpp:

```jpp
quote(value<:Shipment) = value.payload
quote(value<:Express) = value.payload + 100

<:(Express, Shipment) = true
```

`Shipment` and `Express` are ordinary predicates over the compiler's refined
variant types. The native union is defined once by `shipmentType`; the compiler
keeps its owner, tag and `.payload`. The explicit order makes the express rule
more specific than the common rule.

| Incoming shipment | Base price | Quote |
|---|---:|---:|
| Express | 7 cents | 107 cents |
| Standard | 9 cents | 9 cents |

The small prices are fixture data. The producer chooses a tag from a runtime
argument, so both branches must compile. A second producer counts executions;
reading its result must run it once, not once per possible branch.

The remaining checks protect the mechanics behind this use case:

- Returning a refined shipment from `identity` rejoins the native union.
- Named and rest forwarding retain the selected tag and payload.
- An explicitly known express shipment needs only the express method.
- A known tag can select a type at compile time; a runtime tag cannot make a
  type escape at runtime (see `variant_runtime_type`).

This fixture uses Zig grounds for the native union and reflection predicates.
It does not define jpp's storage, allocation or collection model.
