# A captured runtime enum cannot return a type across a callable boundary

The selector captures a runtime enum and returns a type selected from its case.
Its receiver sees a callable value, not that enum as a direct input. This
increment does not lift a case split through fields hidden in a callable, just
as it does not automatically split arbitrary record fields.

The invocation must report a comptime-only result error; it must not evaluate an
undefined runtime capture to manufacture a type. Consuming the selected type
inside the same callback is supported by `do_enum`. Passing the enum as a direct
callback argument also permits the receiver to retain the demand dependency.
