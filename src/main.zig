const std = @import("std");
const heap = std.heap;
const io = std.io;
const ArrayList = std.ArrayList;
const testing = std.testing;

const collect = @import("collect.zig");
const filter = @import("filter.zig");
const util = @import("util.zig");
const ui = @import("tty.zig");

pub fn main() anyerror!void {
    // create an arena allocator to reduce time spent allocating and freeing memory during runtime
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    // TODO: read cmd args

    // read lines on stdin
    var stdin = io.getStdIn().reader();
    var buf = ArrayList(u8).init(allocator);
    defer buf.deinit();

    // read all lines or exit on out of memory
    try util.readAll(&stdin, &buf);

    const delimiter = '\n';
    var options = try collect.collectOptions(allocator, buf.items, delimiter);
    defer options.deinit();

    // TODO: present selection TUI
    var tty = try ui.Tty.init();
    defer tty.deinit();

    try ui.run(allocator, &tty, options);

    // run filter
    // var filtered = try filter.filter(allocator, options.items, query.items);
    // defer filtered.deinit();

    // output all matches

    // for (filtered.items) |string, index| {
    // print the first ten strings with indexes
    //     std.debug.print("{} {s}\n", .{ index, string });
    // }
}
