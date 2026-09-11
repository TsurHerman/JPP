// mixed_vis_fixture.zig — fixture for the EXPORT GATING promise, which
// is observable only ACROSS a file boundary: from another file, @hasDecl
// on a non-pub decl is false — the substrate enforces the gate. `visible`
// is exported (pub); `hidden` is module-internal.

const jpp = @import("jpp.zig");

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
