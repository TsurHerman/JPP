// tailcalls.zig — validate: guaranteed tail calls survive jpp's encoding.
//
// thorin lowers CPS to control-flow form before codegen; jpp never enters
// CPS (ANF + select regions are direct style). but zig's @call(.always_tail)
// gives CHECKED tail calls — a compile error if target/signatures can't,
// never silent stack growth. the emitter marks tail-position calls and
// emits this. proven here: mutual recursion through resolved method
// structs (comptime ctx and all), 10M deep, debug mode — without real
// tail calls this overflows the stack.

const std = @import("std");
const jpp = @import("jpp.zig");

const machine = struct {
    pub const even = jpp.MultiMethod("even", .{jpp.Method(Even)});
    pub const odd = jpp.MultiMethod("odd", .{jpp.Method(Odd)});

    const Even = struct {
        pub const rank = 3;
        pub fn matches(comptime Args: []const type) bool {
            return Args.len == 1 and Args[0] == u64;
        }
        pub fn Ret(comptime ctx: anytype, comptime Args: []const type) type {
            _ = ctx;
            _ = Args;
            return bool;
        }
        pub fn call(comptime ctx: anytype, args: anytype) bool {
            if (args[0] == 0) return true;
            const M = comptime jpp.resolve(ctx, "odd", &.{u64});
            return @call(.always_tail, M.call, .{ ctx, .{args[0] - 1} });
        }
    };

    const Odd = struct {
        pub const rank = 3;
        pub fn matches(comptime Args: []const type) bool {
            return Args.len == 1 and Args[0] == u64;
        }
        pub fn Ret(comptime ctx: anytype, comptime Args: []const type) type {
            _ = ctx;
            _ = Args;
            return bool;
        }
        pub fn call(comptime ctx: anytype, args: anytype) bool {
            if (args[0] == 0) return false;
            const M = comptime jpp.resolve(ctx, "even", &.{u64});
            return @call(.always_tail, M.call, .{ ctx, .{args[0] - 1} });
        }
    };
};

test "mutual tail recursion through resolve, 10M deep, no stack growth" {
    const CTX = .{machine};
    try std.testing.expect(jpp.call(CTX, "even", .{@as(u64, 10_000_000)}));
    try std.testing.expect(!jpp.call(CTX, "even", .{@as(u64, 10_000_001)}));
}
