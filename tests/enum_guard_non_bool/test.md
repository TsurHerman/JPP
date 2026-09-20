# A destination name is not a boolean condition

`destination` returns a string. Using it directly as a guard must fail; a guard
must answer true or false. The valid form compares the string explicitly with
`destination(level) == "operator"`, as the log_labels case demonstrates.
