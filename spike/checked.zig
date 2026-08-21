// checked.zig — hand-transpiled policy module: saturating u8 arithmetic.
// SAME rank (6, exact+exact) as ints' ground methods — this is deliberate
// same-territory shadowing. whoever puts `checked` ahead of `ints` in
// their context gets saturation; everyone else keeps wrapping. the
// override is local: no global table was harmed.

const jpp = @import("jpp.zig");

fn Sat(comptime T: type, comptime op: u8) type {
    return struct {
        pub const rank = 6;
        pub fn matches(comptime Args: []const type) bool {
            return Args.len == 2 and Args[0] == T and Args[1] == T;
        }
        pub fn Ret(comptime ctx: anytype, comptime Args: []const type) type {
            _ = ctx;
            _ = Args;
            return T;
        }
        pub fn call(comptime ctx: anytype, args: anytype) T {
            _ = ctx;
            return switch (op) {
                '+' => args[0] +| args[1], // zig saturating ops
                '-' => args[0] -| args[1],
                '*' => args[0] *| args[1],
                else => unreachable,
            };
        }
    };
}

pub const @"+" = jpp.MultiMethod("+", .{jpp.Method(Sat(u8, '+'))});
pub const @"-" = jpp.MultiMethod("-", .{jpp.Method(Sat(u8, '-'))});
pub const @"*" = jpp.MultiMethod("*", .{jpp.Method(Sat(u8, '*'))});
