// binderprobe.zig — the BINDER under the ratified call convention.
//
// a pack is TWO sections: an ordered TUPLE (positional) then a RECORD
// (named). the convention holds at call sites AND in definitions
// (positional slots are a prefix; `;` opens the named section,
// julia-style). binding never crosses sections: positional slots fill
// by index only, named slots by name only — so the dispatch footgun
// (methods differing only in slot order colliding through named calls)
// is grammatically impossible. named args permute freely among
// THEMSELVES (a record is a set); the method's declared order is the
// canonical form, so permuted spellings converge to ONE bound pack
// type, ONE memoized instance, ONE .so symbol.
//
// raw pack encoding (transpiler, context-blind): positionals as numeric
// field names .@"0", .@"1", ...; named fields verbatim.
//
// methods modeled:
//   scale(x; factor)      = x * factor
//   blend(x; alpha, beta) = x*alpha + x*beta

const std = @import("std");

const Slot = struct { name: []const u8, named: bool };

fn positionOf(comptime name: []const u8) ?usize {
    return std.fmt.parseInt(usize, name, 10) catch null;
}

/// the binder: raw pack TYPE -> bound pack type in declared slot order,
/// or null = this method does not match. replaces `matches: bool` — a
/// boolean cannot say which raw field feeds which slot.
fn bind(comptime slots: []const Slot, comptime Raw: type) ?type {
    comptime {
        const rf = @typeInfo(Raw).@"struct".fields;
        if (rf.len != slots.len) return null; // defaults: not yet ratified
        var types = [_]?type{null} ** slots.len;
        for (rf) |f| {
            if (positionOf(f.name)) |p| {
                // tuple section: index must land on a positional slot
                if (p >= slots.len or slots[p].named) return null;
                if (types[p] != null) return null;
                types[p] = f.type;
            } else {
                // record section: name must land on a NAMED slot — no cross-fill
                const idx = for (slots, 0..) |s, i| {
                    if (s.named and std.mem.eql(u8, s.name, f.name)) break i;
                } else return null;
                if (types[idx] != null) return null;
                types[idx] = f.type;
            }
        }
        var field_names: [slots.len][]const u8 = undefined;
        var field_types: [slots.len]type = undefined;
        for (slots, 0..) |s, i| {
            field_names[i] = s.name;
            field_types[i] = types[i] orelse return null;
        }
        // reified structurally: equal field lists -> the SAME type.
        return @Struct(.auto, null, &field_names, &field_types, &@splat(.{}));
    }
}

/// value-level companion: route raw values into declared slots.
fn bindValues(comptime slots: []const Slot, comptime B: type, raw: anytype) B {
    var out: B = undefined;
    inline for (@typeInfo(@TypeOf(raw)).@"struct".fields) |f| {
        const target = comptime if (positionOf(f.name)) |p| slots[p].name else f.name;
        @field(out, target) = @field(raw, f.name);
    }
    return out;
}

// --- the two methods ------------------------------------------------------------

const scale_slots = [_]Slot{
    .{ .name = "x", .named = false },
    .{ .name = "factor", .named = true },
};

fn scaleInstance(comptime B: type) *const fn (B) f64 {
    return &struct {
        fn call(b: B) f64 {
            return @as(f64, @floatFromInt(b.x)) * b.factor;
        }
    }.call;
}

const blend_slots = [_]Slot{
    .{ .name = "x", .named = false },
    .{ .name = "alpha", .named = true },
    .{ .name = "beta", .named = true },
};

fn blendInstance(comptime B: type) *const fn (B) f64 {
    return &struct {
        fn call(b: B) f64 {
            const xf = @as(f64, @floatFromInt(b.x));
            return xf * b.alpha + xf * b.beta;
        }
    }.call;
}

// --- probes -----------------------------------------------------------------------

test "raw encoding: numeric-named + named fields coexist in one literal" {
    const raw = .{ .@"0" = @as(i64, 3), .factor = @as(f64, 2.0) };
    const fields = @typeInfo(@TypeOf(raw)).@"struct".fields;
    try std.testing.expectEqualStrings("0", fields[0].name);
    try std.testing.expectEqualStrings("factor", fields[1].name);
}

test "scale(3, factor=2.0) binds and evaluates" {
    const raw = .{ .@"0" = @as(i64, 3), .factor = @as(f64, 2.0) };
    const B = bind(&scale_slots, @TypeOf(raw)).?;
    try std.testing.expectEqual(@as(f64, 6.0), scaleInstance(B)(bindValues(&scale_slots, B, raw)));
}

test "no cross-fill: the footgun is a no-match, in both directions" {
    // scale(x=3, factor=2.0): x is a POSITIONAL slot — name cannot fill it
    try std.testing.expect(bind(&scale_slots, struct { x: i64, factor: f64 }) == null);
    // scale(3, 2.0): factor is a NAMED slot — position cannot fill it
    try std.testing.expect(bind(&scale_slots, struct { @"0": i64, @"1": f64 }) == null);
    // unknown name, wrong arity. (double fill is unwritable: zig struct
    // literals reject duplicate field names at the grammar — the raw pack
    // encoding gets that check for free.)
    try std.testing.expect(bind(&scale_slots, struct { @"0": i64, bogus: f64 }) == null);
    try std.testing.expect(bind(&scale_slots, struct { @"0": i64 }) == null);
}

test "named args permute among themselves: ONE bound type, ONE instance" {
    // blend(2, alpha=0.5, beta=0.25)  vs  blend(2, beta=0.25, alpha=0.5)
    const raw_a = .{ .@"0" = @as(i64, 2), .alpha = @as(f64, 0.5), .beta = @as(f64, 0.25) };
    const raw_b = .{ .@"0" = @as(i64, 2), .beta = @as(f64, 0.25), .alpha = @as(f64, 0.5) };

    const A = bind(&blend_slots, @TypeOf(raw_a)).?;
    const B = bind(&blend_slots, @TypeOf(raw_b)).?;
    try std.testing.expect(A == B);
    try std.testing.expect(blendInstance(A) == blendInstance(B));

    try std.testing.expectEqual(@as(f64, 1.5), blendInstance(A)(bindValues(&blend_slots, A, raw_a)));
    try std.testing.expectEqual(@as(f64, 1.5), blendInstance(B)(bindValues(&blend_slots, B, raw_b)));
}
