# Callable value guards do not manufacture runtime inputs

The guarded input is the second method coordinate and holds a callback. Guard
normalization must remap that callable target to the guard's single-input pack,
just as it remaps ordinary operands. This currently unsupported callback result
must produce the deliberate runtime-data qualifier diagnostic, never an internal
Zig index-out-of-bounds error or fabricated callback capture values.
