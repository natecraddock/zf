const std = @import("std");
const heap = std.heap;
const io = std.io;
const ArrayList = std.ArrayList;
const testing = std.testing;

const collect = @import("collect.zig");
const filter = @import("filter.zig");

pub fn main() anyerror!void {
    // create an arena allocator to reduce time spent allocating and freeing memory during runtime
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    // read lines on stdin
    var stdin = io.getStdIn().reader();
    var buf = ArrayList(u8).init(allocator);
    defer buf.deinit();

    // read all lines or exit on out of memory
    try readAllAlloc(&stdin, &buf);

    const delimiter = '\n';
    var options = try collect.collectOptions(allocator, buf.items, delimiter);
    defer options.deinit();

    // TODO: present selection TUI

    // run filter
    var filtered = try filter.filter(allocator, options.items, "outliner");
    defer filtered.deinit();

    // output all matches

    // print the first ten strings with indexes
    for (filtered.items) |string, index| {
        std.debug.print("{} {s}\n", .{ index, string });
    }
}

// similar to the standard library function, but
// doesn't restrict the maximum size of the buffer
fn readAllAlloc(reader: *std.fs.File.Reader, array_list: *ArrayList(u8)) !void {
    // ensure the array starts at a decent size
    try array_list.ensureTotalCapacity(4096);

    var index: usize = 0;
    while (true) {
        array_list.expandToCapacity();
        const slice = array_list.items[index..];
        const read = try reader.readAll(slice);
        index += read;

        if (read != slice.len) {
            array_list.shrinkAndFree(index);
            return;
        }

        try array_list.ensureTotalCapacity(index + 1);
    }
}
