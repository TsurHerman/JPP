# A shipping quote forgot standard delivery

A shipment carries either an express or standard base price. The program has
only an express quote:

```jpp
quote(value<:Express) = value.payload
```

`shipment(shipmentType(), true)` supplies an express sample as **runtime data**.
The type still permits standard shipments, so the generated table must check
that branch too. No standard method exists: compilation must fail and name
`standard` as the missing case.

Adding a standard method or a `Shipment` fallback would repair the program.
The test intentionally keeps that repair absent. See [variant_dispatch](../variant_dispatch/test.md)
for a complete table using one common quote plus an express surcharge.
