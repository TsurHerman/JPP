// Experimental control helpers, deliberately outside the active language.
// Grounds remain context-free. The host explicitly captures a context in a
// deferred call; source callable values and their lexical checks are unbuilt.
const jpp = @import("jpp");
const std = @import("std");

/// Capture arguments now; dispatch and execute when run. Captures are shallow
/// values, not ownership transfers. Keep the full caller context: each word
/// must perform its own normal dependency discovery and collapse.
pub fn DeferredCall(comptime ctx: anytype, comptime word: []const u8, comptime Raw: type) type {
    return struct {
        args: Raw,
        pub const Return = jpp.RetOf(ctx, word, Raw);

        pub fn run(self: @This()) Return {
            return jpp.call(ctx, word, self.args);
        }
    };
}

pub fn bindCall(comptime ctx: anytype, comptime word: []const u8, args: anytype) DeferredCall(ctx, word, @TypeOf(args)) {
    return .{ .args = args };
}

/// The only control primitive: a synchronous body with an unconditional exit
/// action. Errors are ordinary return values; neither action is retried.
/// Cleanup must handle its own failures, since defer cannot return an error.
pub fn ensure(body: anytype, cleanup: anytype) @TypeOf(body).Return {
    if (@TypeOf(cleanup).Return != void)
        @compileError("scope probe: cleanup must return void; handle cleanup errors explicitly");
    defer cleanup.run();
    return body.run();
}

fn Payload(comptime T: type) type {
    return if (@typeInfo(T) == .error_union) @typeInfo(T).error_union.payload else T;
}

fn Errors(comptime T: type) type {
    return if (@typeInfo(T) == .error_union) @typeInfo(T).error_union.error_set else error{};
}

fn Acquisition(comptime ctx: anytype, comptime Request: type) type {
    return jpp.RetOf(ctx, "acquire", std.meta.Tuple(&.{Request}));
}

pub fn ScopeResult(comptime ctx: anytype, comptime Request: type, comptime Job: type) type {
    const A = Acquisition(ctx, Request);
    const R = jpp.RetOf(ctx, "use", std.meta.Tuple(&.{ Job, Payload(A) }));
    // Fallible acquisition adds its errors without widening to anyerror.
    // An infallible acquisition preserves the body's exact return type.
    return if (@typeInfo(A) == .error_union) (Errors(A) || Errors(R))!Payload(R) else R;
}

/// Library-shaped composition of the control primitive. These three words use
/// the real jpp resolver. No method names are added to the compiler.
pub fn withResource(comptime ctx: anytype, request: anytype, job: anytype) ScopeResult(ctx, @TypeOf(request), @TypeOf(job)) {
    const acquired = jpp.call(ctx, "acquire", .{request});
    const resource = if (@typeInfo(@TypeOf(acquired)) == .error_union) try acquired else acquired;
    return ensure(
        bindCall(ctx, "use", .{ job, resource }),
        bindCall(ctx, "release", .{resource}),
    );
}
