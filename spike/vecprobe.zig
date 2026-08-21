// vecprobe.zig — pattern annotation on parametric type-words.
//
// jpp being modeled:
//   Vector{T<:Real, N::int} = zig{ struct { data: [N]T } }   # type-word
//   dot(a::Vector{T,N}, b::Vector{T,N})::T where Float(T)    # pattern method
//
// claims probed:
//   1. a type-word is a comptime fn returning a struct; stamped selectors
//      (auto-stamped by the future struct sugar) let patterns EXTRACT.
//   2. provenance by RE-APPLICATION: A came from Vector iff
//      A == Vector(A.Elem, A.len) — memoized type identity makes
//      application injective; forged stamps cannot pass.
//   3. unification-lite: first occurrence of a free binder BINDS,
//      repetition CONSTRAINS (a and b must share T and N).

const std = @import("std");

fn Vector(comptime T: type, comptime N: usize) type {
    return struct {
        pub const Elem = T; // stamped selectors
        pub const len = N;
        data: [N]T,
    };
}

/// made_by{A, Vector}: extraction + re-application + identity.
fn madeByVector(comptime A: type) bool {
    if (@typeInfo(A) != .@"struct") return false;
    if (!@hasDecl(A, "Elem") or !@hasDecl(A, "len")) return false;
    return A == Vector(A.Elem, A.len);
}

/// the binder of dot(a::Vector{T,N}, b::Vector{T,N})::T where Float(T):
/// returns the bound T (the return type), or null = no match.
fn dotBind(comptime PA: type, comptime PB: type) ?type {
    comptime {
        if (!madeByVector(PA) or !madeByVector(PB)) return null; // provenance
        const T = PA.Elem; // T := elem{A}  — first occurrence binds
        const N = PA.len; //  N := len{A}
        if (PB.Elem != T or PB.len != N) return null; // repetition constrains
        if (T != f32 and T != f64) return null; // where Float(T)
        return T;
    }
}

fn dot(a: anytype, b: anytype) dotBind(@TypeOf(a), @TypeOf(b)).? {
    const T = comptime dotBind(@TypeOf(a), @TypeOf(b)).?;
    var acc: T = 0;
    inline for (0..@TypeOf(a).len) |i| acc += a.data[i] * b.data[i];
    return acc;
}

// --- probes -------------------------------------------------------------------

test "pattern binds T,N and the method dispatches" {
    const V = Vector(f32, 2);
    const a = V{ .data = .{ 1, 2 } };
    const b = V{ .data = .{ 3, 4 } };
    try std.testing.expectEqual(@as(f32, 11), dot(a, b));
}

test "memoization gives type identity: same selectors, same type" {
    try std.testing.expect(Vector(f32, 2) == Vector(f32, 2));
    try std.testing.expect(Vector(f32, 2) != Vector(f32, 3));
}

test "unification rejects mismatched selectors across slots" {
    try std.testing.expect(dotBind(Vector(f32, 2), Vector(f32, 3)) == null); // N differs
    try std.testing.expect(dotBind(Vector(f32, 2), Vector(f64, 2)) == null); // T differs
}

test "where gate: non-Float element type is a quiet no-match" {
    try std.testing.expect(dotBind(Vector(i32, 2), Vector(i32, 2)) == null);
}

test "provenance: an impostor with forged stamps is rejected" {
    const Fake = struct {
        pub const Elem = f32;
        pub const len = 2;
        data: [2]f32,
    };
    try std.testing.expect(!madeByVector(Fake)); // re-application != Fake
    try std.testing.expect(dotBind(Fake, Vector(f32, 2)) == null);
}
