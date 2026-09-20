# A relation between two inputs needs a broader guard model

This source asks dispatch to compare source and destination together. The first
value-guard implementation refines one fixed argument per condition, preserving
pointwise specificity. Correlated multi-input guards are rejected explicitly.
Separate comma-separated guards on separate arguments are supported.
