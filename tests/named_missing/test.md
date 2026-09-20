# An invoice is missing delivery cost

`totalCost(; goods, delivery)` needs two named integer inputs. The call supplies
only `goods = 1`. No default is declared, so compilation must report that no
`totalCost` method matches. Adding `delivery = 0` would make this particular invoice
valid.
