// soprobe.zig — validate: probe a .so for a symbol, use it if present.
// this is the session runtime's warm-cache move: instance keys are
// deterministic, so the exported symbol name IS the content key, and
// "is this instance already compiled in that library" is one dlsym.
// (build.zig can run the same probe at build time and feed the answer
// to comptime via addOptions; comptime proper has no I/O — by design.)

const std = @import("std");

pub fn main() !void {
    // stand-in for a shipped jpp module: the system math library.
    const candidates = [_][]const u8{ "libm.dylib", "libSystem.B.dylib", "libm.so.6" };

    var lib: ?std.DynLib = null;
    var lib_name: []const u8 = "";
    for (candidates) |name| {
        lib = std.DynLib.open(name) catch continue;
        lib_name = name;
        break;
    }
    var l = lib orelse {
        std.debug.print("no candidate library found\n", .{});
        return;
    };
    defer l.close();

    // probe: present -> use the prebuilt binary (cache hit)
    if (l.lookup(*const fn (f64) callconv(.c) f64, "cos")) |cos_fn| {
        std.debug.print("{s}: 'cos' FOUND — using prebuilt: cos(0) = {d}\n", .{ lib_name, cos_fn(0.0) });
    } else {
        std.debug.print("{s}: 'cos' missing — would compile from source\n", .{lib_name});
    }

    // probe an instance that does not exist -> the compile-from-source path
    if (l.lookup(*const fn (f64) callconv(.c) f64, "jpp$deadbeef$ctx0$f64$t1")) |_| {
        std.debug.print("unexpected: fake instance key found\n", .{});
    } else {
        std.debug.print("{s}: fake instance key missing — falls through to source, soundly\n", .{lib_name});
    }
}
