// reals.zig — hand-transpiled reals.jpp: cross-domain convert & promote,
// and the promoting operators. the promoting method re-enters jpp.call
// with the SAME ctx — context reaching downward, as a passed comptime arg.

const jpp = @import("jpp.zig");
const ints = @import("ints.zig");
const floats = @import("floats.zig");

const this_module = @This();
const STATIC = .{ this_module, ints, floats };

pub fn Real(comptime T: type) bool {
    return ints.Integer(T) or floats.Float(T);
}

// --- convert{T}(x): brace+value method set, inlined resolution ---------------
// identity first (core's exact rule), then family rules, then cross-domain.

pub fn convert(comptime T: type, x: anytype) T {
    const X = @TypeOf(x);
    // conditions must be comptime-forced so dead branches are pruned —
    // this is the transpiled form of dispatch: branch selection at comptime.
    if (comptime (X == T)) return x; // core: identity, exact beats every predicate
    if (comptime (ints.Integer(T) and ints.Integer(X))) return ints.convert(T, x);
    if (comptime (floats.Float(T) and floats.Float(X))) return floats.convert(T, x);
    if (comptime (floats.Float(T) and ints.Integer(X))) return @floatFromInt(x);
    if (comptime (ints.Integer(T) and floats.Float(X))) {
        // float -> int: exact, InexactError unless representable
        const r = @round(x);
        if (r != x) @panic("jpp: inexact conversion");
        return @intFromFloat(r);
    }
    @compileError("jpp: no convert rule to " ++ @typeName(T) ++ " from " ++ @typeName(X));
}

// --- promote{A,B}: fused rule table (ints' + floats' + cross-domain) ----------

pub fn @"promote{}"(comptime A: type, comptime B: type) type {
    if (A == B) return A;
    if (ints.Integer(A) and ints.Integer(B)) return ints.@"promote{}"(A, B);
    if (floats.Float(A) and floats.Float(B)) return floats.@"promote{}"(A, B);
    // cross-domain: ints dissolve into floats
    if (ints.Integer(A) and floats.Float(B)) return B;
    if (floats.Float(A) and ints.Integer(B)) return A;
    @compileError("jpp: no promote rule for " ++ @typeName(A) ++ ", " ++ @typeName(B));
}

// --- the promoting operators: op(a<:Real, b<:Real) = op(promote(a,b)...) ------

fn Promoting(comptime op: u8) type {
    return struct {
        pub const rank = 4; // predicate + predicate — loses to exact ground (6)
        pub fn matches(comptime Args: []const type) bool {
            return Args.len == 2 and Real(Args[0]) and Real(Args[1]);
        }
        pub fn Ret(comptime ctx: anytype, comptime Args: []const type) type {
            _ = ctx;
            return @"promote{}"(Args[0], Args[1]);
        }
        pub fn call(comptime ctx: anytype, args: anytype) Ret(ctx, jpp.argTypes(@TypeOf(args))) {
            const T = comptime @"promote{}"(@TypeOf(args[0]), @TypeOf(args[1]));
            // caller's chain stays ahead; reals' static context trails.
            // same-type call hits ground (exact wins) — or the caller's override.
            const ctx2 = comptime jpp.extendAll(ctx, STATIC);
            return jpp.call(ctx2, &[_]u8{op}, .{ convert(T, args[0]), convert(T, args[1]) });
        }
    };
}

pub const @"+" = jpp.MultiMethod("+", .{jpp.Method(Promoting('+'))});
pub const @"-" = jpp.MultiMethod("-", .{jpp.Method(Promoting('-'))});
pub const @"*" = jpp.MultiMethod("*", .{jpp.Method(Promoting('*'))});
