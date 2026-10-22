# cycle_local_ambiguity

Both crossing methods are declared in `a`. Entering the cycle through `b` does
not order methods inside `a`: `b` has no applicable candidate, so `a` is the
winning module and its competing maxima must be ambiguous at the call.
