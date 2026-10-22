// Expected compile failure, checked by scope-probe and probes.
const scope = @import("scope.zig");
const Body = struct {
    pub const Return = void;
    pub fn run(_: @This()) void {}
};
const Cleanup = struct {
    pub const Return = error{CleanupFailed}!void;
    pub fn run(_: @This()) Return {
        return error.CleanupFailed;
    }
};
test "cleanup errors cannot be silently discarded" {
    scope.ensure(Body{}, Cleanup{});
}
