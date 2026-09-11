// build.zig — the orchestrator (ratified: zig's build system drives jpp;
// the transpiler is a peer program, the machinery runs at comptime
// inside generated code).
//
// steps:
//   zig build transpile   tests/dispatch/*.jpp -> gen/*.zig (runs jppc)
//   zig build demo        transpile, compile gen/run.zig, run it
//   zig build test        machinery tests (src/jpp.zig) + language cases (tests/)
//   zig build lang-tests  the language cases, including expected compile errors
//   zig build probes      the validated spike probes

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // the machinery as a named module — tests import it as @import("jpp")
    const jpp_mod = b.createModule(.{
        .root_source_file = b.path("src/jpp.zig"),
        .target = target,
        .optimize = optimize,
    });

    // --- transpile: run jppc over the default case -------------------------
    const jppc = b.addExecutable(.{
        .name = "jppc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/jppc.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const transpile = b.addRunArtifact(jppc);
    transpile.setCwd(b.path("."));
    const transpile_step = b.step("transpile", "Transpile tests/dispatch/*.jpp -> gen/*.zig");
    transpile_step.dependOn(&transpile.step);

    // --- demo: compile and run the default tree's program -------------------
    const demo_exe = b.addExecutable(.{
        .name = "demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("gen/run.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    demo_exe.step.dependOn(&transpile.step); // gen/ must exist first
    const run_demo = b.addRunArtifact(demo_exe);
    const demo_step = b.step("demo", "Transpile and run the demo program");
    demo_step.dependOn(&run_demo.step);

    // --- test: the machinery's tests live INLINE in src/jpp.zig -------------
    const mach_tests = b.addTest(.{ .root_module = jpp_mod });
    const test_step = b.step("test", "Machinery tests + language test cases");
    test_step.dependOn(&b.addRunArtifact(mach_tests).step);

    // --- lang-tests: each DIRECT child folder of tests/ is a CASE.
    // jppc finds PROGRAMS inside it (root modules that define main());
    // the generated artifact self-reports `[case] PASS|FAIL`, exit 0/1.
    // adding a case = mkdir under tests/ — this list is walked, not written.
    //
    // NEGATIVE cases: a folder containing `expect.err` never runs — the
    // promise IS a compile error. jppc transpiles it, then zig compiles
    // it EXPECTING failure, and the error must contain the file's text.
    const lang_step = b.step("lang-tests", "Run jpp language cases (self-judging programs)");
    for (caseFolders(b)) |name| {
        const src = b.fmt("tests/{s}", .{name});
        const gen = b.fmt("tests/.gen/{s}", .{name});
        const tr = b.addRunArtifact(jppc);
        tr.setCwd(b.path("."));
        tr.addArg(src);
        tr.addArg(gen);
        if (expectedError(b, name)) |needle| {
            const neg = b.addSystemCommand(&.{
                b.graph.zig_exe, "build-exe", "-fno-emit-bin", "--cache-dir", ".zig-cache",
            });
            neg.addArg(b.fmt("tests/.gen/{s}/run.zig", .{name}));
            neg.setCwd(b.path("."));
            neg.step.dependOn(&tr.step);
            neg.expectExitCode(1); // compile SUCCESS fails the case
            neg.expectStdErrMatch(needle);
            lang_step.dependOn(&neg.step);
            continue;
        }
        const case_exe = b.addExecutable(.{
            .name = b.fmt("case_{s}", .{name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("tests/.gen/{s}/run.zig", .{name})),
                .target = target,
                .optimize = optimize,
            }),
        });
        case_exe.step.dependOn(&tr.step);
        const run_case = b.addRunArtifact(case_exe);
        lang_step.dependOn(&run_case.step); // exit code IS the verdict
    }
    test_step.dependOn(lang_step); // `zig build test` = the whole truth

    // --- probes: the validated spikes ---------------------------------------
    const probe_files = [_][]const u8{
        "spike/interpprobe.zig",
        "spike/enumprobe.zig",
        "spike/binderprobe.zig",
        "spike/vecprobe.zig",
    };
    const probes_step = b.step("probes", "Run the validated spike probes");
    for (probe_files) |p| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(p),
                .target = target,
                .optimize = optimize,
            }),
        });
        probes_step.dependOn(&b.addRunArtifact(t).step);
    }
}

/// `tests/<case>/expect.err` marks a NEGATIVE case; content = the
/// substring the compile error must contain.
fn expectedError(b: *std.Build, name: []const u8) ?[]const u8 {
    const data = b.build_root.handle.readFileAlloc(
        b.graph.io,
        b.fmt("tests/{s}/expect.err", .{name}),
        b.allocator,
        .unlimited,
    ) catch return null;
    return std.mem.trim(u8, data, " \t\r\n");
}

fn caseFolders(b: *std.Build) []const []const u8 {
    const io = b.graph.io;
    var dir = b.build_root.handle.openDir(io, "tests", .{ .iterate = true }) catch
        @panic("jpp: missing tests/");
    defer dir.close(io);
    var names: std.ArrayList([]const u8) = .empty;
    var it = dir.iterate();
    while (it.next(io) catch @panic("jpp: tests/ walk")) |ent| {
        if (ent.kind != .directory) continue;
        if (ent.name.len == 0 or ent.name[0] == '.') continue;
        names.append(b.allocator, b.dupe(ent.name)) catch @panic("oom");
    }
    const slice = names.items;
    std.mem.sort([]const u8, slice, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lessThan);
    return slice;
}
