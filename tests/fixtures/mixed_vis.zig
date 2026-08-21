// mixed_vis.zig — fixture for the EXPORT GATING promise.
// `visible` is exported (pub); `hidden` is module-internal (no pub).
// zig enforces the boundary: from another file, @hasDecl on a non-pub
// decl is false — the resolver cannot see it, by substrate guarantee.

const jpp = @import("jpp");

fn G(comptime s: []const u8) type {
    return struct {
        pub fn Ret(comptime B: type) type {
            _ = B;
            return []const u8;
        }
        pub fn run(bound: anytype) []const u8 {
            _ = bound;
            return s;
        }
    };
}

pub const visible = jpp.MultiMethod("visible", &.{.{
    .name = "visible",
    .signature = &.{.{ .name = "x", .qual = .bare }},
    .body = .{ .ground = G("from fixture") },
}});

const hidden = jpp.MultiMethod("hidden", &.{.{
    .name = "hidden",
    .signature = &.{.{ .name = "x", .qual = .bare }},
    .body = .{ .ground = G("should be invisible") },
}});
