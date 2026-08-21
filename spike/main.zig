// main.zig — hand-transpiled main.jpp.
// `using ints; using floats; using reals` becomes the CTX tuple; every
// surface call a + b becomes jpp.call(CTX, "+", .{a, b}).

const std = @import("std");
const jpp = @import("jpp.zig");
const ints = @import("ints.zig");
const floats = @import("floats.zig");
const reals = @import("reals.zig");
const checked = @import("checked.zig");
const lib = @import("lib.zig");

const CTX = .{ ints, floats, reals, lib };

// a second calling context: same imports, but `using checked` FIRST.
// order is priority — earlier wins rank ties.
const CHECKED_CTX = .{checked} ++ CTX;

pub fn main() void {
    // main.jpp: const a = 5; const b = 5.5; var c = a + b
    const a: i64 = 5;
    const b: f64 = 5.5;
    const c = jpp.call(CTX, "+", .{ a, b });
    std.debug.print("i64 + f64  -> {s}: {d}\n", .{ @typeName(@TypeOf(c)), c });

    // same-type: resolves straight to the exact ground method
    const d = jpp.call(CTX, "+", .{ @as(i64, 40), @as(i64, 2) });
    std.debug.print("i64 + i64  -> {s}: {d}\n", .{ @typeName(@TypeOf(d)), d });

    // mixed signedness, julia verbatim: int32 + uint64 -> uint64
    const e = jpp.call(CTX, "+", .{ @as(i32, 7), @as(u64, 3) });
    std.debug.print("i32 + u64  -> {s}: {d}\n", .{ @typeName(@TypeOf(e)), e });

    // mixed width ints: wider wins
    const f = jpp.call(CTX, "*", .{ @as(i16, 300), @as(i64, 1000) });
    std.debug.print("i16 * i64  -> {s}: {d}\n", .{ @typeName(@TypeOf(f)), f });

    // wrapping ground arithmetic (julia semantics): u8 200*2 == 144
    const g = jpp.call(CTX, "*", .{ @as(u8, 200), @as(u8, 2) });
    std.debug.print("u8  * u8   -> {s}: {d}  (wraps)\n", .{ @typeName(@TypeOf(g)), g });

    // floats: wider wins
    const h = jpp.call(CTX, "-", .{ @as(f32, 1.5), @as(f64, 0.25) });
    std.debug.print("f32 - f64  -> {s}: {d}\n", .{ @typeName(@TypeOf(h)), h });

    // --- ordered context: same rank, position breaks the tie ---------------
    // checked's saturating u8 `+` shadows ints' wrapping ground (both rank 6)
    const s1 = jpp.call(CHECKED_CTX, "+", .{ @as(u8, 200), @as(u8, 200) });
    std.debug.print("u8  + u8   -> {s}: {d}  (checked ctx: saturates)\n", .{ @typeName(@TypeOf(s1)), s1 });

    // --- the founding sentence, running -------------------------------------
    // lib.double never imported checked. same call, two contexts:
    const w = jpp.call(CTX, "double", .{@as(u8, 200)});
    std.debug.print("double(u8 200) base ctx    -> {d}  (wraps)\n", .{w});
    const s2 = jpp.call(CHECKED_CTX, "double", .{@as(u8, 200)});
    std.debug.print("double(u8 200) checked ctx -> {d}  (caller override reaches inside lib)\n", .{s2});
}
