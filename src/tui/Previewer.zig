//! Manages child processes used for previewing information about the selected line

const heap = std.heap;
const mem = std.mem;
const os = std.os;
const process = std.process;
const std = @import("std");
const vaxis = @import("vaxis");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Child = process.Child;
const Event = @import("ui.zig").State.Event;

const Previewer = @This();

/// Thread-local arena allocator
arena: heap.ArenaAllocator,

shell: []const u8,
cmd_parts: [2][]const u8,

arg: []const u8 = "",
last_arg: []const u8 = "",

output: []const u8 = "",

thread: ?std.Thread = null,
semaphore: std.Thread.Semaphore,

pub fn init(cmd: []const u8) Previewer {
    // heap.page_allocator is thread-safe, but the ArenaAllocator from the main thread is not.
    // Create a new arena for this thread.
    var arena = heap.ArenaAllocator.init(heap.page_allocator);

    const shell = process.getEnvVarOwned(arena.allocator(), "SHELL") catch "/bin/sh";

    var iter = std.mem.tokenizeSequence(u8, cmd, "{}");
    const cmd_parts = [2][]const u8{
        iter.next() orelse cmd,
        iter.next() orelse "",
    };

    return .{
        .arena = arena,
        .shell = shell,
        .cmd_parts = cmd_parts,
        .semaphore = std.Thread.Semaphore{},
    };
}

pub fn startThread(previewer: *Previewer, loop: *vaxis.Loop(Event)) !void {
    previewer.thread = try std.Thread.spawn(.{}, threadLoop, .{ previewer, loop });
}

fn threadLoop(previewer: *Previewer, loop: *vaxis.Loop(Event)) !void {
    const allocator = previewer.arena.allocator();

    while (true) {
        previewer.semaphore.wait();

        // If the arg is already being previewed we don't need to do any work
        if (mem.eql(u8, previewer.arg, previewer.last_arg)) {
            continue;
        }

        const command = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ previewer.cmd_parts[0], previewer.arg, previewer.cmd_parts[1] });

        var child = Child.init(&.{ previewer.shell, "-c", command }, allocator);
        child.stdin_behavior = .Close;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        try child.spawn();

        // This is what the child.collectOutput() function does, but instead of raising an
        // error when the max_output_bytes is reached use the collected output
        var poller = std.io.poll(allocator, enum { stdout, stderr }, .{
            .stdout = child.stdout.?,
            .stderr = child.stderr.?,
        });
        defer poller.deinit();

        const max_output_bytes = 4096 * 4;
        while (try poller.poll()) {
            if (poller.fifo(.stdout).count > max_output_bytes) break;
            if (poller.fifo(.stderr).count > max_output_bytes) break;
        }
        _ = try child.kill();

        // Because zf uses an arena allocator for everything, this could possibly grow to
        // use a lot of memory. But zf is a short-lived process so this should be fine.
        if (poller.fifo(.stderr).count > 0) {
            previewer.output = try poller.fifo(.stderr).toOwnedSlice();
        } else {
            previewer.output = try poller.fifo(.stdout).toOwnedSlice();
        }

        if (!std.unicode.utf8ValidateSlice(previewer.output)) {
            previewer.output = "Invalid utf8";
        }

        previewer.last_arg = try allocator.dupe(u8, previewer.arg);
        loop.postEvent(.preview_ready);
    }
}

pub fn spawn(previewer: *Previewer, arg: []const u8) void {
    previewer.arg = arg;
    previewer.semaphore.post();
}

const testing = std.testing;

test Previewer {
    // dummy loop for testing
    var loop = vaxis.Loop(Event){
        .tty = undefined,
        .vaxis = undefined,
    };

    // create a previewer in a different thread
    var previewer = Previewer.init("echo foo {} baz");
    try previewer.startThread(&loop);

    // send a message to that thread to spawn a child process
    previewer.spawn("bar");

    // wait for the child to finish and see if the output was as expected
    const event = loop.nextEvent();
    try testing.expectEqual(.preview_ready, event);
    try testing.expectEqualStrings("foo bar baz\n", previewer.output);
}
