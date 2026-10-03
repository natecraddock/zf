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

thread: ?std.Io.Future(ThreadLoopError!void) = null,
semaphore: std.Io.Semaphore = .{},

pub fn init(gpa: std.mem.Allocator, env_map: *std.process.Environ.Map, cmd: []const u8) !Previewer {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    const alloc = arena.allocator();
    const shell = try alloc.dupe(u8, env_map.get("SHELL") orelse "/bin/sh");

    var iter = std.mem.tokenizeSequence(u8, try alloc.dupe(u8, cmd), "{}");
    const cmd_parts = [2][]const u8{
        iter.next() orelse cmd,
        iter.next() orelse "",
    };

    return .{
        .arena = arena,
        .shell = shell,
        .cmd_parts = cmd_parts,
        .semaphore = .{},
    };
}

pub fn deinit(previewer: *Previewer, io: std.Io) void {
    if (previewer.thread) |*t| t.cancel(io) catch {};
    previewer.arena.deinit();
}

pub fn startThread(previewer: *Previewer, io: std.Io, loop: *vaxis.Loop(Event)) !void {
    previewer.thread = try io.concurrent(threadLoop, .{ previewer, io, loop });
}

// Vaxis does not return a bounded error set,
// so type reflection is required here.
const ThreadLoopError = @typeInfo(@typeInfo(@TypeOf(Previewer.threadLoop)).@"fn".return_type.?).error_union.error_set;

fn threadLoop(previewer: *Previewer, io: std.Io, loop: *vaxis.Loop(Event)) !void {
    const allocator = previewer.arena.allocator();

    while (true) {
        try previewer.semaphore.wait(io);

        const command = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ previewer.cmd_parts[0], previewer.arg, previewer.cmd_parts[1] });

        const child = try run(
            allocator,
            io,
            &.{ previewer.shell, "-c", command },
        );

        previewer.output = output: {
            if (child.stderr.len > 0) {
                break :output child.stderr;
            }
            break :output child.stdout;
        };

        if (!std.unicode.utf8ValidateSlice(previewer.output)) {
            previewer.output = "Invalid utf8";
        }

        try loop.postEvent(.preview_ready);
    }
}

/// This is a fork of std.process.run from Zig 0.16.0. This version changes the
/// behavior when the size limit it reached for output. Instead of erroring, it
/// will return the output that has been gathered so far.
pub fn run(gpa: std.mem.Allocator, io: std.Io, argv: []const []const u8) !std.process.RunResult {
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .close,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    defer child.kill(io);

    var multi_reader_buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
    var multi_reader: std.Io.File.MultiReader = undefined;
    multi_reader.init(gpa, io, multi_reader_buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer multi_reader.deinit();

    const stdout_reader = multi_reader.reader(0);
    const stderr_reader = multi_reader.reader(1);

    while (multi_reader.fill(64, .none)) |_| {
        if (stdout_reader.buffered().len > 4 * 4096) break;
        if (stderr_reader.buffered().len > 4 * 4096) break;
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    }

    try multi_reader.checkAnyError();

    const term = try child.wait(io);

    const stdout_slice = try multi_reader.toOwnedSlice(0);
    errdefer gpa.free(stdout_slice);

    const stderr_slice = try multi_reader.toOwnedSlice(1);
    errdefer gpa.free(stderr_slice);

    return .{
        .stdout = stdout_slice,
        .stderr = stderr_slice,
        .term = term,
    };
}

pub fn spawn(previewer: *Previewer, io: std.Io, arg: []const u8) void {
    previewer.arg = arg;
    previewer.semaphore.post(io);
}

const testing = std.testing;

test Previewer {
    const io = std.testing.io;
    const alloc = std.testing.allocator;

    var env_map = try std.testing.environ.createMap(alloc);
    defer env_map.deinit();

    // dummy loop for testing
    var loop: vaxis.Loop(Event) = .init(io, undefined, undefined);
    _ = &loop;

    // // create a previewer in a different thread
    var previewer = try Previewer.init(alloc, &env_map, "echo foo {} baz");
    defer previewer.deinit(io);

    try previewer.startThread(io, &loop);

    // send a message to that thread to spawn a child process
    previewer.spawn(io, "bar");

    // wait for the child to finish and see if the output was as expected
    const event = try loop.nextEvent();
    try testing.expectEqual(.preview_ready, event);
    try testing.expectEqualStrings("foo bar baz\n", previewer.output);
}
