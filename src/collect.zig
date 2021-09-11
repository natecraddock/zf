const std = @import("std");
const ArrayList = std.ArrayList;

// read the options from the buffer
pub fn collectOptions(allocator: *std.mem.Allocator, buf: []const u8, delimiter: u8) !ArrayList([]const u8) {
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

const testing = std.testing;

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
