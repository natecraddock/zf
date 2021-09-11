const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zf", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run zf");
    run_step.dependOn(&run_cmd.step);

    const tests = b.step("test", "Run tests");
    addTest(b, tests, "src/main.zig");
    addTest(b, tests, "src/collect.zig");
    addTest(b, tests, "src/filter.zig");
}

fn addTest(b: *std.build.Builder, step: *std.build.Step, name: []const u8) void {
    const t = b.addTest(name);
    step.dependOn(&t.step);
}
