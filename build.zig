const std = @import("std");

fn dir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub const package = std.build.Pkg{
    .name = "zf",
    .source = .{ .path = dir() ++ "/src/lib.zig" },
};

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zf", "src/main.zig");
    exe.addPackagePath("ziglyph", "lib/ziglyph/src/ziglyph.zig");
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

    var exe_tests = b.addTest("src/main.zig");
    exe_tests.addPackagePath("ziglyph", "libs/ziglyph/src/ziglyph.zig");
    exe_tests.setBuildMode(mode);

    const tests = b.step("test", "Run tests");
    tests.dependOn(&exe_tests.step);
}
