# A runtime temperature needs a runtime guard

This increment evaluates guards from facts already known during dispatch, such
as an enum branch's exact case. The temperature here is ordinary runtime data.
The compiler must reject its guard clearly, rather than guess a value or pretend
that every float has been checked. Numeric interval dispatch remains unbuilt.
