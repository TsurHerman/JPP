# binding_call

Applying a local non-callable value must fail rather than silently dispatch to
the same-spelled module word. Callable values now use this same application path;
this case binds the integer 7, so rejection occurs during semantic compilation.
