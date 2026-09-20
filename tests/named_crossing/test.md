# Two score rules disagree about which field matters

One `chooseScore` method constrains `home` to int64; the other constrains `away`.
Supplying both as integers matches both methods. Neither dominates pointwise, even
though the declarations list fields in opposite orders. Compilation must report
`AMBIGUOUS`.
