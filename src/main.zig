const std = @import("std");
const heap = std.heap;
const io = std.io;
const ArrayList = std.ArrayList;
const testing = std.testing;

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
    var options = try collectOptions(allocator, buf.items, delimiter);
    defer options.deinit();

    // TODO: present selection TUI

    // run filter
    var filtered = try filter(allocator, options.items, "outliner");
    defer filtered.deinit();

    // output all matches

    // print the first ten strings with indexes
    for (filtered.items) |string, index| {
        std.debug.print("{} {s}\n", .{ index, string });
    }
}

// read the options from the buffer
fn collectOptions(allocator: *std.mem.Allocator, buf: []const u8, delimiter: u8) !ArrayList([]const u8) {
    var options = ArrayList([]const u8).init(allocator);

    // find delimiters
    var start: usize = 0;
    for (buf) |char, index| {
        if (char == delimiter) {
            // add to arraylist only if slice is not all delimiters
            if (index - start != 0) {
                try options.append(buf[start..index]);
            }
            start = index + 1;
        }
    }
    // catch the end if stdio didn't end in a delimiter
    if (start < buf.len) {
        try options.append(buf[start..]);
    }

    return options;
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

fn filter(allocator: *std.mem.Allocator, options: [][]const u8, query: []const u8) !ArrayList([]const u8) {
    var filtered = ArrayList([]const u8).init(allocator);

    for (options) |option, index| {
        if (std.mem.count(u8, option, query) > 0) {
            try filtered.append(option);
        }
    }

    return filtered;
}

test "collect options whitespace" {
    var options = try collectOptions(std.testing.allocator, "first second third fourth", ' ');
    defer options.deinit();

    try testing.expectEqual(@as(usize, 4), options.items.len);
    try testing.expectEqualStrings("first", options.items[0]);
    try testing.expectEqualStrings("second", options.items[1]);
    try testing.expectEqualStrings("third", options.items[2]);
    try testing.expectEqualStrings("fourth", options.items[3]);
}

test "collect options newline" {
    var options = try collectOptions(std.testing.allocator, "first\nsecond\nthird\nfourth", '\n');
    defer options.deinit();

    try testing.expectEqual(@as(usize, 4), options.items.len);
    try testing.expectEqualStrings("first", options.items[0]);
    try testing.expectEqualStrings("second", options.items[1]);
    try testing.expectEqualStrings("third", options.items[2]);
    try testing.expectEqualStrings("fourth", options.items[3]);
}

test "collect options whitespace" {
    var options = try collectOptions(std.testing.allocator, "   first second   third fourth   ", ' ');
    defer options.deinit();

    try testing.expectEqual(@as(usize, 4), options.items.len);
}
