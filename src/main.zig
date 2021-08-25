const std = @import("std");
const heap = std.heap;
const io = std.io;
const ArrayList = std.ArrayList;

pub fn main() anyerror!void {
    // create an arena allocator to reduce time spent allocating and freeing memory during runtime
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    const BUF_SIZE = 4096 * 2 * 2;
    var capacity: usize = BUF_SIZE;
    var position: usize = 0;
    var buf = try allocator.alloc(u8, capacity);

    // read lines on stdin and echo
    // var stdin = io.bufferedReader(io.getStdIn().reader()).reader();
    var stdin = io.getStdIn().reader();
    while (stdin.readNoEof(buf[position..])) {
        // read the buf to capacity, make more room
        capacity += BUF_SIZE;
        position += BUF_SIZE;
        buf = try allocator.realloc(buf, capacity);
    } else |err| {
        // read until eof, shrink remaining
    }

    // find delimiters
    const delimiter = '\n';
    var strings = ArrayList([]u8).init(allocator);
    defer strings.deinit();

    var start: usize = 0;
    for (buf) |char, index| {
        if (char == delimiter) {
            // add to arraylist
            try strings.append(buf[start..index]);
            start = index + 1;
        }
    }

    // print the first ten strings with indexes
    for (strings.items) |string, index| {
        if (index == 10) break;
        std.debug.print("{} {s}\n", .{ index, string });
    }
}
