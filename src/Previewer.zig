//! Manages child processes used for previewing information about the selected line

const mem = std.mem;
const process = std.process;
const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Child = process.Child;
const Loop = @import("Loop.zig");

const Previewer = @This();

allocator: Allocator,
loop: *Loop,

shell: []const u8,
cmd_parts: [2][]const u8,

current_arg: []const u8 = "",

child: ?Child = null,
stdout: ArrayList(u8),
stderr: ArrayList(u8),

pub fn init(allocator: Allocator, loop: *Loop, cmd: []const u8, arg: []const u8) !Previewer {
    const shell = process.getEnvVarOwned(allocator, "SHELL") catch "/bin/sh";

    var iter = std.mem.tokenizeSequence(u8, cmd, "{}");
    var cmd_parts = [2][]const u8{
        iter.next() orelse cmd,
        iter.next() orelse "",
    };

    var previewer = Previewer{
        .allocator = allocator,
        .loop = loop,
        .shell = shell,
        .cmd_parts = cmd_parts,
        .stdout = ArrayList(u8).init(allocator),
        .stderr = ArrayList(u8).init(allocator),
    };
    try previewer.spawn(arg);

    return previewer;
}

pub fn reset(previewer: *Previewer) !void {
    previewer.stdout.clearRetainingCapacity();
    previewer.stderr.clearRetainingCapacity();
    if (previewer.child) |*child| {
        _ = try child.kill();
    }
}

pub fn spawn(previewer: *Previewer, arg: []const u8) !void {
    // If the arg is already being previewed we don't need to do any work
    if (mem.eql(u8, arg, previewer.current_arg)) {
        return;
    }

    try previewer.reset();

    const command = try std.fmt.allocPrint(previewer.allocator, "{s}{s}{s} | expand -t4", .{ previewer.cmd_parts[0], arg, previewer.cmd_parts[1] });

    var child = Child.init(&.{ previewer.shell, "-c", command }, previewer.allocator);
    child.stdin_behavior = .Close;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();

    previewer.loop.setChild(child.stdout.?.handle, child.stderr.?.handle);
    previewer.child = child;
    previewer.current_arg = try previewer.allocator.dupe(u8, arg);
}

pub fn read(previewer: *Previewer, stream: enum { stdout, stderr }) !void {
    if (previewer.child) |*child| {
        var bytes_read: usize = 0;
        while (true) {
            var buf: [1024]u8 = undefined;
            const len = switch (stream) {
                .stdout => try child.stdout.?.read(&buf),
                .stderr => try child.stderr.?.read(&buf),
            };
            bytes_read += len;
            if (len == 0) break;

            switch (stream) {
                .stdout => try previewer.stdout.appendSlice(buf[0..len]),
                .stderr => try previewer.stderr.appendSlice(buf[0..len]),
            }
        }

        if (bytes_read == 0) {
            _ = try child.kill();
            previewer.child = null;
            previewer.loop.clearChild();
        }
    }
}

pub fn lines(previewer: *Previewer) std.mem.SplitIterator(u8, .scalar) {
    if (previewer.stderr.items.len > 0) {
        return std.mem.splitScalar(u8, previewer.stderr.items, '\n');
    }
    return std.mem.splitScalar(u8, previewer.stdout.items, '\n');
}
