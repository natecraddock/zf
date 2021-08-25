const std = @import("std");
const heap = std.heap;
const io = std.io;
const ArrayList = std.ArrayList;

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

    // find delimiters
    // const delimiter = ' ';
    const delimiter = '\n';
    var strings = ArrayList([]u8).init(allocator);
    defer strings.deinit();

    var start: usize = 0;
    for (buf.items) |char, index| {
        if (char == delimiter) {
            // std.debug.print("found char newline\n", .{});
            // add to arraylist
            try strings.append(buf.items[start..index]);
            start = index + 1;
        } else {
            // std.debug.print("found char {c}\n", .{char});
        }
    }

    // print the first ten strings with indexes
    for (strings.items) |string, index| {
        if (index == 10) break;
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
            array_list.shrinkAndFree(read);
            return;
        }

        try array_list.ensureTotalCapacity(index + 1);
    }
}
