# Parcel height cannot stand in for weight

`shippingWeight` declares the named input `grams`. The call provides `height`
instead. Compilation must fail: an unknown label must not fill a required slot by
position.
