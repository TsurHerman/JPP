// build.zig — the orchestrator (ratified: zig's build system drives jpp;
// the transpiler is a peer program, the machinery runs at comptime
// inside generated code).
//
// steps:
//   zig build transpile   demo/*.jpp -> gen/*.zig (runs jppc)
//   zig build demo        transpile, compile gen/run.zig, run it
//   zig build test        machinery tests (src/jpp.zig) + boundary tests (tests/)
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

    // --- transpile: run jppc over demo/ ------------------------------------
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
    const transpile_step = b.step("transpile", "Transpile demo/*.jpp -> gen/*.zig");
    transpile_step.dependOn(&transpile.step);

    // --- demo: compile and run the generated program ------------------------
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

    // --- test: machinery + language-promise boundary tests ------------------
    const mach_tests = b.addTest(.{ .root_module = jpp_mod });

    const fixture_mod = b.createModule(.{
        .root_source_file = b.path("tests/fixtures/mixed_vis.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "jpp", .module = jpp_mod }},
    });
    const boundary_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/boundaries.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "jpp", .module = jpp_mod },
                .{ .name = "mixed_vis", .module = fixture_mod },
            },
        }),
    });

    const test_step = b.step("test", "Machinery + boundary (language-promise) tests");
    test_step.dependOn(&b.addRunArtifact(mach_tests).step);
    test_step.dependOn(&b.addRunArtifact(boundary_tests).step);

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
