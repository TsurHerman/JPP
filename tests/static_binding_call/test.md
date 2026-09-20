# A type alias does not declare a constructor

`OffsetWidth = uint32` binds a native type value. `OffsetWidth()` then tries to
call it as if it were a method. Compilation must report that the constant is
not callable; reading its value is valid, calling it has no application
protocol yet. A same-spelled word must not be selected accidentally.
