// ints.zig — hand-transpiled ints.jpp.
// ground loop `for T in (...) { +(a::T,b::T)::T = zig{a +% b} ... }`
// becomes a comptime generator instantiated per T; the method set decl
// carries the jpp surface name verbatim: pub const @"+" = ...

const jpp = @import("jpp.zig");

pub const int_types = .{ i8, i16, i32, i64, u8, u16, u32, u64 };

// --- predicates ------------------------------------------------------------

pub fn Integer(comptime T: type) bool {
    inline for (int_types) |U| if (T == U) return true;
    return false;
}

pub fn Signed(comptime T: type) bool {
    return Integer(T) and @typeInfo(T).int.signedness == .signed;
}

pub fn Unsigned(comptime T: type) bool {
    return Integer(T) and !Signed(T);
}

// --- promote{A,B}: transpiled brace methods, inlined resolution -------------
// (full transpiler would emit these as a @"promote{}" method set; the
//  where-clauses become the branch conditions below.)

pub fn @"promote{}"(comptime A: type, comptime B: type) type {
    const ia = @typeInfo(A).int;
    const ib = @typeInfo(B).int;
    // same signedness: wider wins
    if (ia.signedness == ib.signedness)
        return if (ia.bits >= ib.bits) A else B;
    // mixed, julia verbatim: signed strictly wider wins, else the unsigned
    const S = if (ia.signedness == .signed) A else B;
    const U = if (ia.signedness == .signed) B else A;
    return if (@bitSizeOf(S) > @bitSizeOf(U)) S else U;
}

// --- ground zero: wrapping arithmetic (julia semantics) ----------------------

fn Ground(comptime T: type, comptime op: u8) type {
    return struct {
        pub const rank = 6; // exact + exact
        pub fn matches(comptime Args: []const type) bool {
            return Args.len == 2 and Args[0] == T and Args[1] == T;
        }
        pub fn Ret(comptime ctx: anytype, comptime Args: []const type) type {
            _ = ctx;
            _ = Args;
            return T;
        }
        pub fn call(comptime ctx: anytype, args: anytype) T {
            _ = ctx; // axioms take no context — the one-way door
            return switch (op) {
                '+' => args[0] +% args[1],
                '-' => args[0] -% args[1],
                '*' => args[0] *% args[1],
                else => unreachable,
            };
        }
    };
}

fn groundSet(comptime op: u8) [int_types.len]type {
    comptime var out: [int_types.len]type = undefined;
    inline for (int_types, 0..) |T, i| out[i] = jpp.Method(Ground(T, op));
    return out;
}

pub const @"+" = jpp.MultiMethod("+", groundSet('+'));
pub const @"-" = jpp.MultiMethod("-", groundSet('-'));
pub const @"*" = jpp.MultiMethod("*", groundSet('*'));

// int -> int, exact (@intCast traps on overflow in safe builds)
pub fn convert(comptime T: type, x: anytype) T {
    return @intCast(x);
}
