// minimal probe: plain mutual tail calls, no generics, no jpp machinery.
const std = @import("std");

fn even(n: u64) bool {
    if (n == 0) return true;
    return @call(.always_tail, odd, .{n - 1});
}

fn odd(n: u64) bool {
    if (n == 0) return false;
    return @call(.always_tail, even, .{n - 1});
}

pub fn main() void {
    const n: u64 = 10_000_000;
    std.debug.print("even({d}) = {}\n", .{ n, even(n) });
}
