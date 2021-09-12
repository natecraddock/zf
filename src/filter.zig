const std = @import("std");
const ArrayList = std.ArrayList;

pub fn filter(allocator: *std.mem.Allocator, options: [][]const u8, query: []const u8) !ArrayList([]const u8) {
    var filtered = ArrayList([]const u8).init(allocator);

    for (options) |option, index| {
        if (std.mem.count(u8, option, query) > 0) {
            try filtered.append(option);
        }
    }

    return filtered;
}

const testing = std.testing;

test "simple filter" {
    var options = [_][]const u8{ "abc", "xyz", "abcdef" };

    // match all strings containing "abc"
    var filtered = try filter(testing.allocator, options[0..], "abc");
    defer filtered.deinit();

    var expected = [_][]const u8{ "abc", "abcdef" };
    try testing.expectEqualSlices([]const u8, expected[0..], filtered.items);
}
