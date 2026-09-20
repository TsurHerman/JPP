# A quote cannot sometimes return cents and sometimes text

The express method returns the shipment's integer price. The standard method
returns the string `"standard"`. A runtime shipment could select either method,
so this call has no single result type and compilation must fail.

Dispatch must not invent a sum type or silently convert one result. A real
quote API should return one common price type, or explicitly construct the
same declared result union from both methods.
