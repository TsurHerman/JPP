// floats.zig — hand-transpiled floats.jpp.

const jpp = @import("jpp.zig");

pub const float_types = .{ f16, f32, f64 };

pub fn Float(comptime T: type) bool {
    inline for (float_types) |U| if (T == U) return true;
    return false;
}

// promote{F,G}: wider wins
pub fn @"promote{}"(comptime F: type, comptime G: type) type {
    return if (@bitSizeOf(F) >= @bitSizeOf(G)) F else G;
}

// --- ground zero (IEEE 754) ---------------------------------------------------

fn Ground(comptime T: type, comptime op: u8) type {
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
                '+' => args[0] + args[1],
                '-' => args[0] - args[1],
                '*' => args[0] * args[1],
                else => unreachable,
            };
        }
    };
}

fn groundSet(comptime op: u8) [float_types.len]type {
    comptime var out: [float_types.len]type = undefined;
    inline for (float_types, 0..) |T, i| out[i] = jpp.Method(Ground(T, op));
    return out;
}

pub const @"+" = jpp.MultiMethod("+", groundSet('+'));
pub const @"-" = jpp.MultiMethod("-", groundSet('-'));
pub const @"*" = jpp.MultiMethod("*", groundSet('*'));

pub fn convert(comptime T: type, x: anytype) T {
    return @floatCast(x);
}
