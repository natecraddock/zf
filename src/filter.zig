const std = @import("std");
const ArrayList = std.ArrayList;

pub fn filter(allocator: *std.mem.Allocator, options: [][]const u8, query: []const u8) !ArrayList([]const u8) {
    var filtered = ArrayList([]const u8).init(allocator);

    for (options) |option, index| {
        if (match(option, query)) {
            try filtered.append(option);
        }
    }

    return filtered;
}

fn match(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var index: usize = 0;
    for (haystack) |char| {
        if (needle[index] == char) {
            index += 1;
        }

        // all chars have matched
        if (index == needle.len) return true;
    }

    return false;
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
