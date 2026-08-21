// gen_main.zig — harness for the first MACHINE-GENERATED jpp module.
// gen_double.zig is produced by `zig run src/emit.zig` from the AST value
// in src/ast.zig. if this runs correctly, the pipeline's last stage is real.

const std = @import("std");
const jpp = @import("jpp.zig");
const ints = @import("ints.zig");
const floats = @import("floats.zig");
const reals = @import("reals.zig");
const gen = @import("gen_double.zig");

const CTX = .{ ints, floats, reals, gen };

pub fn main() void {
    const a = jpp.call(CTX, "double", .{@as(u8, 200)});
    std.debug.print("generated double(u8 200)  = {d}  (expect 144, wraps)\n", .{a});
    const b = jpp.call(CTX, "double", .{@as(i64, 21)});
    std.debug.print("generated double(i64 21)  = {d}  (expect 42)\n", .{b});
    const c = jpp.call(CTX, "double", .{@as(f32, 1.25)});
    std.debug.print("generated double(f32 1.25) = {d}  (expect 2.5)\n", .{c});
}
