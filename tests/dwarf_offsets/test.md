# Native enums compose a DWARF offset reader

The dwarf facade selects uint32/uint64 from Zig's actual std.dwarf.Format.
Binary.Input selects byte order from std.builtin.Endian. An ordinary readOffset
call composes both decisions and returns std.Io.Reader.Error!u64 in every arm.
No format, enum identity, branch or IO rule is special-cased in the compiler.

All four runtime combinations are checked against the native DWARF algorithm,
including high-bit unsigned values, exact cursor advancement and producer order.
Truncated inputs preserve EndOfStream without consuming a partial field. Known
cases can select type values and need only their own method, even through helpers.
Sequential reads prove that only the chosen IO operation executes.

A second program imports an audit policy for uint32/little only. It reaches the
inner binary reader through the dwarf facade and exercise module. Other choices
retain their original behavior, and the base program has no policy.

The reader, byte slices and allocation are foreign Zig fixture details, not a jpp
ownership or collection model. Native error unions are forwarded intact; general
jpp error handling remains unbuilt.

Code-generation inspection (2026-09-20, Zig 0.16, aarch64-macos, ReleaseFast):
an exported probe calling this generated module with two runtime selectors retains
width and endian branches, 32/64-bit loads and the appropriate byte swaps. A
second probe with explicit static Format.32/Endian.little fields contains one
32-bit load and zero-extension; only reader buffer/error branches remain. This
is an inspected optimizer result, not a portable instruction-count promise.
