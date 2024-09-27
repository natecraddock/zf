const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pie = b.option(bool, "pie", "Build a Position Independent Executable");

    // Expose zf as a Zig module
    const zf_module = b.addModule("zf", .{
        .root_source_file = b.path("src/zf/zf.zig"),
    });

    const dep_vaxis = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });

    const tui = b.addExecutable(.{
        .name = "zf",
        .root_source_file = b.path("src/tui/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    tui.root_module.addImport("zf", zf_module);
    tui.root_module.addImport("vaxis", dep_vaxis.module("vaxis"));
    tui.pie = pie;

    b.installArtifact(tui);

    const run_cmd = b.addRunArtifact(tui);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run zf");
    run_step.dependOn(&run_cmd.step);

    const tui_tests = b.addTest(.{
        .root_source_file = b.path("src/tui/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    tui_tests.root_module.addImport("zf", zf_module);
    tui_tests.root_module.addImport("vaxis", dep_vaxis.module("vaxis"));

    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/zf/zf.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_tui_tests = b.addRunArtifact(tui_tests);
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tui_tests.step);
    test_step.dependOn(&run_lib_tests.step);
}
