// A resource scope over the ACTIVE jpp dispatcher, not spike/jpp.zig.
// Run: zig build scope-probe (also included in zig build probes).
const std = @import("std");
const jpp = @import("jpp");
const scope = @import("scope.zig");

const State = struct {
    trace: [32]u8 = undefined,
    count: usize = 0,
    productions: usize = 0,
    live: bool = false,
    pooled: ?[]u8 = null,

    fn event(self: *@This(), value: u8) void {
        self.trace[self.count] = value;
        self.count += 1;
    }

    fn events(self: *const @This()) []const u8 {
        return self.trace[0..self.count];
    }
};

const Request = struct { state: *State, id: u8 = 1, fail: bool = false };
const Buffer = struct { state: *State, id: u8, bytes: []u8 };
const LeaseRequest = struct { state: *State };
const Lease = struct { state: *State };
const Job = enum { size, fail };
const AcquireError = error{ Denied, OutOfMemory };
const BodyError = error{BodyFailed};

fn produced(state: *State) Request {
    state.productions += 1;
    return .{ .state = state };
}

const Acquire = struct {
    pub fn Ret(comptime _: type) type {
        return AcquireError!Buffer;
    }
    pub fn run(b: anytype) Ret(@TypeOf(b)) {
        const r = b.request;
        r.state.event(r.id);
        if (r.fail) return error.Denied;
        std.debug.assert(!r.state.live);
        const bytes = try std.testing.allocator.alloc(u8, 8);
        r.state.live = true;
        return .{ .state = r.state, .id = r.id, .bytes = bytes };
    }
};

const AcquireLease = struct {
    pub fn Ret(comptime _: type) type {
        return Lease;
    }
    pub fn run(b: anytype) Lease {
        std.debug.assert(!b.request.state.live);
        b.request.state.live = true;
        b.request.state.event(2);
        return .{ .state = b.request.state };
    }
};

const Destroy = struct {
    pub fn Ret(comptime _: type) type {
        return void;
    }
    pub fn run(b: anytype) void {
        std.debug.assert(b.resource.state.live);
        b.resource.state.event(20 + b.resource.id);
        b.resource.state.live = false;
        std.testing.allocator.free(b.resource.bytes);
    }
};

const ReleaseLease = struct {
    pub fn Ret(comptime _: type) type {
        return void;
    }
    pub fn run(b: anytype) void {
        std.debug.assert(b.resource.state.live);
        b.resource.state.event(22);
        b.resource.state.live = false;
    }
};

const BeforeRelease = struct {
    pub fn Ret(comptime _: type) type {
        return void;
    }
    pub fn run(_: anytype) void {}
};

const AuditRelease = struct {
    pub fn Ret(comptime _: type) type {
        return void;
    }
    pub fn run(b: anytype) void {
        std.debug.assert(b.resource.state.live);
        b.resource.state.event(30);
    }
};

const Recycle = struct {
    pub fn Ret(comptime _: type) type {
        return void;
    }
    pub fn run(b: anytype) void {
        const state = b.resource.state;
        std.debug.assert(state.live and state.pooled == null);
        state.event(40);
        state.live = false;
        state.pooled = b.resource.bytes;
    }
};

fn Compute(comptime extra: usize) type {
    return struct {
        pub fn Ret(comptime _: type) type {
            return BodyError!usize;
        }
        pub fn run(b: anytype) Ret(@TypeOf(b)) {
            std.debug.assert(b.resource.state.live);
            b.resource.state.event(if (extra == 0) 10 else 12);
            return b.resource.bytes.len + extra;
        }
    };
}

const Fail = struct {
    pub fn Ret(comptime _: type) type {
        return BodyError!usize;
    }
    pub fn run(b: anytype) Ret(@TypeOf(b)) {
        std.debug.assert(b.resource.state.live);
        b.resource.state.event(11);
        return error.BodyFailed;
    }
};

const UseLease = struct {
    pub fn Ret(comptime _: type) type {
        return bool;
    }
    pub fn run(b: anytype) bool {
        std.debug.assert(b.resource.state.live);
        b.resource.state.event(10);
        return true;
    }
};

const View = struct {
    pub fn Ret(comptime _: type) type {
        return []const u8;
    }
    pub fn run(b: anytype) []const u8 {
        return b.resource.bytes;
    }
};

fn slot(comptime name: []const u8, comptime T: type) jpp.Slot {
    return .{ .name = name, .qual = .{ .exact = T } };
}

fn unary(comptime name: []const u8, comptime parameter: []const u8, comptime T: type, comptime G: type) jpp.Method {
    return .{ .name = name, .signature = &.{slot(parameter, T)}, .body = .{ .ground = G } };
}

// Equivalent ordinary bodies:
//   use(Job.size, resource::Buffer) = compute(resource)
//   release(resource::Buffer) = { beforeRelease(resource); destroy(resource) }
// Their dependencies are visible to jpp's normal context collapse.
const Resources = struct {
    pub const STATIC = .{ @This(), Leaves };
    pub const acquire = jpp.MultiMethod("acquire", &.{
        unary("acquire", "request", Request, Acquire),
        unary("acquire", "request", LeaseRequest, AcquireLease),
    });
    pub const use = jpp.MultiMethod("use", &.{
        .{
            .name = "use",
            .signature = &.{ .{ .name = "job", .qual = .{ .enum_value = jpp.EnumValue(Job.size) } }, slot("resource", Buffer) },
            .body = .{ .ops = .{ .ops = &.{.{ .callee = "compute", .args = &.{.{ .param = 1 }} }}, .result = .{ .local = 0 } } },
        },
        .{
            .name = "use",
            .signature = &.{ .{ .name = "job", .qual = .{ .enum_value = jpp.EnumValue(Job.fail) } }, slot("resource", Buffer) },
            .body = .{ .ground = Fail },
        },
        .{ .name = "use", .signature = &.{ slot("job", void), slot("resource", Lease) }, .body = .{ .ground = UseLease } },
    });
    pub const view = jpp.MultiMethod("view", &.{unary("view", "resource", Buffer, View)});
    pub const release = jpp.MultiMethod("release", &.{
        .{
            .name = "release",
            .signature = &.{slot("resource", Buffer)},
            .body = .{ .ops = .{
                .ops = &.{
                    .{ .callee = "beforeRelease", .args = &.{.{ .param = 0 }} },
                    .{ .callee = "destroy", .args = &.{.{ .param = 0 }} },
                },
                .result = .{ .local = 1 },
            } },
        },
        unary("release", "resource", Lease, ReleaseLease),
    });
};

const Leaves = struct {
    pub const compute = jpp.MultiMethod("compute", &.{unary("compute", "resource", Buffer, Compute(0))});
    pub const beforeRelease = jpp.MultiMethod("beforeRelease", &.{unary("beforeRelease", "resource", Buffer, BeforeRelease)});
    pub const destroy = jpp.MultiMethod("destroy", &.{unary("destroy", "resource", Buffer, Destroy)});
};

const Audit = struct {
    pub const compute = jpp.MultiMethod("compute", &.{unary("compute", "resource", Buffer, Compute(100))});
    pub const beforeRelease = jpp.MultiMethod("beforeRelease", &.{unary("beforeRelease", "resource", Buffer, AuditRelease)});
};

const Pool = struct {
    pub const release = jpp.MultiMethod("release", &.{unary("release", "resource", Buffer, Recycle)});
};

test "acquire once, use while live, release once after producing the result" {
    var state: State = .{};
    try std.testing.expectEqual(8, try scope.withResource(.{Resources}, produced(&state), Job.size));
    try std.testing.expectEqual(1, state.productions);
    try std.testing.expect(!state.live);
    try std.testing.expectEqualSlices(u8, &.{ 1, 10, 21 }, state.events());
}

test "caller overrides reach dependencies of both body and deferred cleanup" {
    var state: State = .{};
    try std.testing.expectEqual(108, try scope.withResource(.{ Audit, Resources }, produced(&state), Job.size));
    try std.testing.expectEqualSlices(u8, &.{ 1, 12, 30, 21 }, state.events());
}

test "a caller can replace destruction with return to a pool" {
    var state: State = .{};
    defer if (state.pooled) |bytes| std.testing.allocator.free(bytes);
    try std.testing.expectEqual(8, try scope.withResource(.{ Pool, Resources }, produced(&state), Job.size));
    try std.testing.expect(state.pooled != null and !state.live);
    try std.testing.expectEqualSlices(u8, &.{ 1, 10, 40 }, state.events());
}

test "cleanup selection preserves caller context order" {
    var state: State = .{};
    try std.testing.expectEqual(8, try scope.withResource(.{ Resources, Pool }, produced(&state), Job.size));
    try std.testing.expect(state.pooled == null and !state.live);
    try std.testing.expectEqualSlices(u8, &.{ 1, 10, 21 }, state.events());
}

test "body error survives cleanup; acquisition error arms skip body and cleanup" {
    var state: State = .{};
    try std.testing.expectError(error.BodyFailed, scope.withResource(.{ Audit, Resources }, produced(&state), Job.fail));
    try std.testing.expectEqualSlices(u8, &.{ 1, 11, 30, 21 }, state.events());
    state = .{};
    try std.testing.expectError(error.Denied, scope.withResource(.{Resources}, Request{ .state = &state, .fail = true }, Job.size));
    try std.testing.expectEqualSlices(u8, &.{1}, state.events());
    try std.testing.expect(!state.live);
    try std.testing.expect(scope.ScopeResult(.{Resources}, Request, Job) == (AcquireError || BodyError)!usize);
}

test "the same protocol manages an infallible non-memory lease" {
    var state: State = .{};
    const result = scope.withResource(.{Resources}, LeaseRequest{ .state = &state }, {});
    try std.testing.expect(@TypeOf(result) == bool and result);
    try std.testing.expect(!state.live);
    try std.testing.expectEqualSlices(u8, &.{ 2, 10, 22 }, state.events());
}

test "deferred calls capture values without executing and retain runtime enum dispatch" {
    var state: State = .{};
    const resource = try jpp.call(.{Resources}, "acquire", .{produced(&state)});
    var job = Job.size;
    const body = scope.bindCall(.{Resources}, "use", .{ job, resource });
    const cleanup = scope.bindCall(.{ Audit, Resources }, "release", .{resource});
    job = .fail;
    try std.testing.expectEqualSlices(u8, &.{1}, state.events());
    try std.testing.expectEqual(8, try scope.ensure(body, cleanup));
    try std.testing.expectEqualSlices(u8, &.{ 1, 10, 30, 21 }, state.events());
}

fn Nested(comptime fail_acquisition: bool) type {
    return struct {
        inner: *State,
        outer: *State,
        pub const Return = (AcquireError || BodyError)!usize;
        pub fn run(self: @This()) Return {
            std.debug.assert(self.outer.live);
            const result = scope.withResource(.{Resources}, Request{ .state = self.inner, .id = 2, .fail = fail_acquisition }, Job.fail);
            std.debug.assert(self.outer.live and !self.inner.live);
            self.outer.event(15); // inner has exited; outer has not
            return result;
        }
    };
}

test "nested failure cleans the inner scope before the outer scope" {
    inline for (.{ false, true }) |fail_acquisition| {
        var outer: State = .{};
        var inner: State = .{};
        const resource = try jpp.call(.{Resources}, "acquire", .{produced(&outer)});
        const result = scope.ensure(
            Nested(fail_acquisition){ .inner = &inner, .outer = &outer },
            scope.bindCall(.{Resources}, "release", .{resource}),
        );
        try std.testing.expectError(if (fail_acquisition) error.Denied else error.BodyFailed, result);
        try std.testing.expectEqualSlices(u8, &.{ 1, 15, 21 }, outer.events());
        try std.testing.expectEqualSlices(u8, if (fail_acquisition) &.{2} else &.{ 2, 11, 22 }, inner.events());
        try std.testing.expect(!outer.live and !inner.live);
    }
}

test "limit: deterministic cleanup does not prevent a borrowed result escaping" {
    var state: State = .{};
    const resource = try jpp.call(.{Resources}, "acquire", .{produced(&state)});
    const escaped = scope.ensure(
        scope.bindCall(.{Resources}, "view", .{resource}),
        scope.bindCall(.{Resources}, "release", .{resource}),
    );
    // Inspect only the copied slice descriptor, NEVER its freed allocation.
    try std.testing.expectEqual(8, escaped.len);
    try std.testing.expect(!state.live);
    try std.testing.expectEqualSlices(u8, &.{ 1, 21 }, state.events());
}
