// lib.zig — hand-transpiled library module:
//
//   using ints; using floats; using reals
//   double(x) = x + x
//
// lib knows NOTHING about checked. yet a caller whose context puts
// checked ahead gets saturating `+` inside double — the method table is
// derived from the caller, not from base. this is the founding sentence
// of the language, running.

const jpp = @import("jpp.zig");
const ints = @import("ints.zig");
const floats = @import("floats.zig");
const reals = @import("reals.zig");

const this_module = @This();

// lib's static context: itself + its imports (what `using` transpiles to)
const STATIC = .{ this_module, ints, floats, reals };

const Double = struct {
    pub const rank = 1; // one bare argument
    pub fn matches(comptime Args: []const type) bool {
        return Args.len == 1;
    }
    pub fn Ret(comptime ctx: anytype, comptime Args: []const type) type {
        _ = ctx;
        return Args[0];
    }
    pub fn call(comptime ctx: anytype, args: anytype) Ret(ctx, jpp.argTypes(@TypeOf(args))) {
        // effective context: caller's chain ahead, lib's static behind
        const ctx2 = comptime jpp.extendAll(ctx, STATIC);
        return jpp.call(ctx2, "+", .{ args[0], args[0] });
    }
};

pub const double = jpp.MultiMethod("double", .{jpp.Method(Double)});
