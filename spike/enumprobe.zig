// enumprobe.zig — validate the runtime-enum -> comptime-dispatch bridge.
//
// claim 1: a pack built from a comptime-known enum value carries the VALUE
//          in its type (anonymous literals make comptime-known initializers
//          comptime FIELDS). so value-exact methods are visible to
//          pack-type matching — dispatch on values needs no new mechanism.
// claim 2: `switch (x) { inline else => |v| ... }` makes v comptime per
//          arm, so the ground machinery can lift a runtime enum field to
//          comptime and re-enter ordinary dispatch — the collected arms
//          ARE the switch table, one per variant, folded by LLVM.
//
// jpp surface being modeled:
//   step(x::Mode)    = "default"
//   step(Mode.fast)  = "FAST"        # exact value, rank 3, beats bare

const std = @import("std");

const Mode = enum { fast, safe, debug };

// --- pack-type inspection (what the ground matcher will do) ------------------

fn packField(comptime P: type, comptime i: usize) std.builtin.Type.StructField {
    return @typeInfo(P).@"struct".fields[i];
}

/// comptime field value of the pack TYPE, or null if the field is runtime
fn comptimeValue(comptime P: type, comptime i: usize, comptime T: type) ?T {
    const f = packField(P, i);
    if (!f.is_comptime) return null;
    return f.defaultValue().?;
}

// --- the word `step`, dispatch on pack type -----------------------------------

fn matchesFast(comptime P: type) bool {
    const fields = @typeInfo(P).@"struct".fields;
    if (fields.len != 1 or fields[0].type != Mode) return false;
    return (comptimeValue(P, 0, Mode) orelse return false) == .fast;
}

fn step(pack: anytype) []const u8 {
    const P = @TypeOf(pack);
    // exact-value method: visible only when the pack type carries the value
    if (comptime matchesFast(P)) return "FAST";

    const f = comptime packField(P, 0);
    if (comptime (f.type == Mode and !f.is_comptime)) {
        // the BRIDGE: lift runtime enum to comptime, re-enter dispatch.
        // each inline arm rebuilds the pack with the value comptime-known.
        switch (pack[0]) {
            inline else => |v| return step(.{v}),
        }
    }
    return "default"; // bare method step(x::Mode)
}

// --- probes -------------------------------------------------------------------

test "claim 1: comptime-known enum value lives in the pack TYPE" {
    const P = @TypeOf(.{Mode.fast});
    const f = @typeInfo(P).@"struct".fields[0];
    try std.testing.expect(f.is_comptime);
    try std.testing.expect(f.defaultValue().? == Mode.fast);
}

test "comptime call: value-exact method wins without any switch" {
    try std.testing.expectEqualStrings("FAST", step(.{Mode.fast}));
    try std.testing.expectEqualStrings("default", step(.{Mode.safe}));
}

test "claim 2: runtime enum routes through the bridge to the same methods" {
    var m: Mode = undefined; // runtime value, opaque to comptime
    m = .fast;
    try std.testing.expectEqualStrings("FAST", step(.{m}));
    m = .safe;
    try std.testing.expectEqualStrings("default", step(.{m}));
    m = .debug;
    try std.testing.expectEqualStrings("default", step(.{m}));
}

// --- ruling: "just nest it" — nesting emerges from recursion -------------------
// the bridge lifts ONE runtime field per re-entry, left to right; a pack
// with several runtime enums nests automatically. cartesian product =
// the user's own specialization budget.
//
//   twin(a::Mode, b::Mode)       = "default"
//   twin(Mode.fast, Mode.fast)   = "FF"

fn matchesFF(comptime P: type) bool {
    const fields = @typeInfo(P).@"struct".fields;
    if (fields.len != 2 or fields[0].type != Mode or fields[1].type != Mode) return false;
    if ((comptimeValue(P, 0, Mode) orelse return false) != .fast) return false;
    return (comptimeValue(P, 1, Mode) orelse return false) == .fast;
}

fn twin(pack: anytype) []const u8 {
    const P = @TypeOf(pack);
    if (comptime matchesFF(P)) return "FF";
    if (comptime !packField(P, 0).is_comptime) {
        switch (pack[0]) {
            inline else => |a| return twin(.{ a, pack[1] }),
        }
    }
    if (comptime !packField(P, 1).is_comptime) {
        switch (pack[1]) {
            inline else => |b| return twin(.{ pack[0], b }),
        }
    }
    return "default";
}

test "two runtime fields: nested table emerges from one-field-per-re-entry" {
    var a: Mode = undefined;
    var b: Mode = undefined;
    a = .fast;
    b = .fast;
    try std.testing.expectEqualStrings("FF", twin(.{ a, b }));
    b = .safe;
    try std.testing.expectEqualStrings("default", twin(.{ a, b }));
    // mixed comptime/runtime: only one lift needed
    try std.testing.expectEqualStrings("FF", twin(.{ Mode.fast, a }));
}

// --- ruling: integer ranges ride zig's range arms ------------------------------
// integers can't inline-else (2^64 arms); they bridge through DECLARED
// range patterns as zig range arms; the else arm is the unconstrained
// method. `inline 0...9 => |v|` lifts each value in range to comptime.
//
//   digit(x::u8)                 = "big"
//   digit(x::u8) where x <= 9    = "small"   # range pattern

fn matchesSmall(comptime P: type) bool {
    const fields = @typeInfo(P).@"struct".fields;
    if (fields.len != 1 or fields[0].type != u8) return false;
    return (comptimeValue(P, 0, u8) orelse return false) <= 9;
}

fn digit(pack: anytype) []const u8 {
    const P = @TypeOf(pack);
    if (comptime matchesSmall(P)) return "small";
    if (comptime !packField(P, 0).is_comptime) {
        switch (pack[0]) {
            // arms = the range patterns declared by methods in context
            inline 0...9 => |v| return digit(.{v}),
            // else = methods that don't constrain the value
            else => return "big",
        }
    }
    return "big";
}

test "integer range pattern bridges through zig range arms" {
    try std.testing.expectEqualStrings("small", digit(.{@as(u8, 5)})); // comptime
    var x: u8 = undefined;
    x = 7;
    try std.testing.expectEqualStrings("small", digit(.{x}));
    x = 200;
    try std.testing.expectEqualStrings("big", digit(.{x}));
}
