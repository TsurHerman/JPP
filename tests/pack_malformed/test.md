# Two commas leave a missing tuple element

`(1,,2)` contains a separator with no expression beside it. The frontend must report
the unexpected comma, not invent an empty slot.
