const std = @import("std");
const heap = std.heap;
const io = std.io;

const ArrayList = std.ArrayList;

const filter = @import("filter.zig");
const util = @import("util.zig");
const ui = @import("ui.zig");

pub fn main() anyerror!void {
    // create an arena allocator to reduce time spent allocating and freeing memory during runtime
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // TODO: read cmd args

    // read lines on stdin
    var stdin = io.getStdIn().reader();
    var buf = ArrayList(u8).init(allocator);
    defer buf.deinit();

    // read all lines or exit on out of memory
    try util.readAll(&stdin, &buf);

    const delimiter = '\n';
    var candidates = try filter.collectCandidates(allocator, buf.items, delimiter);
    defer candidates.deinit();

    var terminal = try ui.Terminal.init();

    var selected = try ui.run(allocator, &terminal, candidates);
    try ui.cleanUp(&terminal);
    terminal.deinit();

    if (selected) |res| {
        defer res.deinit();
        const stdout = std.io.getStdOut().writer();
        try stdout.print("{s}\n", .{res.items});
    }
}

test {
    _ = @import("filter.zig");
    _ = @import("util.zig");
}
