// boundaries.zig — tests of the LANGUAGE'S PROMISES against the real
// machinery (src/jpp.zig via @import("jpp")). the probes in spike/
// validated mechanisms in isolation; these tests pin the promises on
// the library the transpiler actually emits against.
//
// catalog and coverage map: tests/README.md. this file is the SEED —
// the systematic boundary-writing phase extends it.

const std = @import("std");
const jpp = @import("jpp");
const mixed_vis = @import("mixed_vis");

// --- shared fixtures ---------------------------------------------------------

fn GroundConst(comptime v: i64) type {
    return struct {
        pub fn Ret(comptime B: type) type {
            _ = B;
            return i64;
        }
        pub fn run(bound: anytype) i64 {
            _ = bound;
            return v;
        }
    };
}

fn GroundAdd(comptime T: type) type {
    return struct {
        pub fn Ret(comptime B: type) type {
            _ = B;
            return T;
        }
        pub fn run(bound: anytype) T {
            return @field(bound, "a") +% @field(bound, "b");
        }
    };
}

fn GroundPlus100(comptime T: type) type {
    return struct {
        pub fn Ret(comptime B: type) type {
            _ = B;
            return T;
        }
        pub fn run(bound: anytype) T {
            return @field(bound, "a") + @field(bound, "b") + 100;
        }
    };
}

const ints = struct {
    pub const @"+" = jpp.MultiMethod("+", &.{.{
        .name = "+",
        .signature = &.{
            .{ .name = "a", .qual = .{ .exact = i64 } },
            .{ .name = "b", .qual = .{ .exact = i64 } },
        },
        .body = .{ .ground = GroundAdd(i64) },
    }});
};

const lib = struct {
    // double(x) = x + x — a data body; meaning of `+` comes from context
    pub const double = jpp.MultiMethod("double", &.{.{
        .name = "double",
        .signature = &.{.{ .name = "x", .qual = .bare }},
        .body = .{ .ops = .{ .ops = &.{
            .{ .callee = "+", .args = &.{ .{ .param = 0 }, .{ .param = 0 } } },
        }, .result = .{ .local = 0 } } },
    }});
};

const R1 = struct { i64 };

fn Inst(comptime ctx: anytype, comptime word: []const u8, comptime Raw: type) type {
    return struct {
        fn go(raw: Raw) jpp.RetOf(ctx, word, Raw) {
            return jpp.call(ctx, word, raw);
        }
    };
}

// --- PROMISE: exports gate everything (the substrate enforces pub) ------------

test "export gating: a non-pub word is invisible to resolution" {
    // `visible` resolves from the fixture; `hidden` (non-pub) does not
    // exist as far as the resolver is concerned — zig's visibility IS
    // the export gate.
    var n: i64 = 1;
    n += 0;
    try std.testing.expectEqualStrings("from fixture", jpp.call(.{mixed_vis}, "visible", .{n}));
    try std.testing.expect(comptime jpp.resolve(.{mixed_vis}, "hidden", R1) == null);
}

// --- PROMISE: context collapse — the resolving module owns the instance -------

test "collapse: an inert caller converges to the library's own instance" {
    const inert = struct {
        pub const unrelated = 17;
    };
    const full = jpp.canon(.{ inert, ints, lib }, "double");
    const own = jpp.canon(.{ ints, lib }, "double");
    try std.testing.expect(&Inst(full, "double", R1).go == &Inst(own, "double", R1).go);

    // a caller that actually shadows `+` keeps its own instance
    const shadow = struct {
        pub const @"+" = jpp.MultiMethod("+", &.{.{
            .name = "+",
            .signature = &.{
                .{ .name = "a", .qual = .{ .exact = i64 } },
                .{ .name = "b", .qual = .{ .exact = i64 } },
            },
            .body = .{ .ground = GroundPlus100(i64) },
        }});
    };
    const shadowed = jpp.canon(.{ shadow, ints, lib }, "double");
    try std.testing.expect(&Inst(shadowed, "double", R1).go != &Inst(own, "double", R1).go);
}

// --- PROMISE: delegation — selection from M, propagation from the caller ------

test "delegation: M.f picks M's method, the body still speaks the caller's language" {
    const my_double = struct { // caller's own double: always 0
        pub const double = jpp.MultiMethod("double", &.{.{
            .name = "double",
            .signature = &.{.{ .name = "x", .qual = .{ .exact = i64 } }},
            .body = .{ .ground = GroundConst(0) },
        }});
    };
    const plus100 = struct { // caller's own `+`
        pub const @"+" = jpp.MultiMethod("+", &.{.{
            .name = "+",
            .signature = &.{
                .{ .name = "a", .qual = .{ .exact = i64 } },
                .{ .name = "b", .qual = .{ .exact = i64 } },
            },
            .body = .{ .ground = GroundPlus100(i64) },
        }});
    };
    const CALLER = .{ my_double, plus100, ints, lib };

    var n: i64 = 21;
    n += 0;
    // unqualified: the caller's own double wins
    try std.testing.expectEqual(@as(i64, 0), jpp.call(CALLER, "double", .{n}));
    // delegated to lib: lib's method, but `+` resolves in the CALLER's
    // context — 21+21+100 = 142
    try std.testing.expectEqual(@as(i64, 142), jpp.delegate(.{ ints, lib }, CALLER, "double", .{n}));
}
