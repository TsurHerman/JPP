# Two shipping rules improve different arguments

One quote method requires an express shipment and accepts any extra charge.
The other accepts a broader shipment input but requires an `int64` charge.
An express shipment with an `int64` charge matches both.

The first method is more specific on the shipment; the second is more specific
on the charge. Neither wins on both arguments, so compilation must report
ambiguity. Injecting the union's branch must preserve ordinary pointwise
specificity rather than adding the ranks together.
