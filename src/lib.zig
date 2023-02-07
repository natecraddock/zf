const filter = @import("filter.zig");
const std = @import("std");
const testing = std.testing;

/// rank a given string against a slice of tokens
pub fn rank(
    str: []const u8,
    filename: ?[]const u8,
    tokens: []const []const u8,
    case_sensitive: bool,
) f64 {
    var total_rank: f64 = 0;
    for (tokens) |token| {
        if (filter.rankToken(str, filename, token, case_sensitive)) |r| {
            total_rank += r;
        } else return -1.0;
    }
    return total_rank;
}

/// rank a given string against a single token
pub fn rankToken(
    str: []const u8,
    filename: ?[]const u8,
    token: []const u8,
    case_sensitive: bool,
) ?f64 {
    return filter.rankToken(str, filename, token, case_sensitive);
}

test "rank library interface" {
    try testing.expect(rank("abcdefg", null, &.{ "a", "z" }, false) == -1);
    try testing.expect(rank("abcdefg", null, &.{ "a", "b" }, false) != -1);
    try testing.expect(rank("abcdefg", null, &.{ "a", "B" }, true) == -1);
    try testing.expect(rank("aBcdefg", null, &.{ "a", "B" }, true) != -1);
    try testing.expect(rank("a/path/to/file", "file", &.{"zig"}, false) == -1);
    try testing.expect(rank("a/path/to/file", "file", &.{ "path", "file" }, false) != -1);

    try testing.expect(rankToken("abcdefg", null, "a", false) != null);
    try testing.expect(rankToken("abcdefg", null, "z", false) == null);
    try testing.expect(rankToken("abcdefG", null, "G", true) != null);
    try testing.expect(rankToken("abcdefg", null, "A", true) == null);
    try testing.expect(rankToken("a/path/to/file", "file", "file", false) != null);
    try testing.expect(rankToken("a/path/to/file", "file", "zig", false) == null);
}

/// a start and ending index for a token match
pub const Range = filter.Range;

/// compute matching ranges given a string and a slice of tokens
pub fn highlight(
    str: []const u8,
    filename: ?[]const u8,
    ranges: []Range,
    tokens: []const []const u8,
    case_sensitive: bool,
) void {
    for (tokens) |token, i| {
        ranges[i] = filter.highlightToken(str, filename, token, case_sensitive);
    }
}

/// compute matching ranges given a string and a single token
pub fn highlightToken(
    str: []const u8,
    filename: ?[]const u8,
    token: []const u8,
    case_sensitive: bool,
) Range {
    return filter.highlightToken(str, filename, token, case_sensitive);
}

fn testHighlight(
    expectedRanges: []const Range,
    str: []const u8,
    filename: ?[]const u8,
    tokens: []const []const u8,
    case_sensitive: bool,
) !void {
    var ranges = try testing.allocator.alloc(Range, tokens.len);
    defer testing.allocator.free(ranges);
    highlight(str, filename, ranges, tokens, case_sensitive);
    try testing.expectEqualSlices(Range, expectedRanges, ranges);
}

test "highlight library interface" {
    try testHighlight(&.{ .{ .start = 0, .end = 0 }, .{ .start = 5, .end = 5 } }, "abcdef", null, &.{ "a", "f" }, false);
    try testHighlight(&.{ .{ .start = 0, .end = 0 }, .{ .start = 5, .end = 5 } }, "abcdeF", null, &.{ "a", "F" }, true);
    try testHighlight(&.{ .{ .start = 2, .end = 5 }, .{ .start = 10, .end = 13 } }, "a/path/to/file", "file", &.{ "path", "file" }, false);

    try testing.expectEqual(Range{ .start = 0, .end = 0 }, highlightToken("abcdef", null, "a", false));
    try testing.expectEqual(Range{ .start = 5, .end = 5 }, highlightToken("abcdeF", null, "F", true));
    try testing.expectEqual(Range{ .start = 10, .end = 13 }, highlightToken("a/path/to/file", "file", "file", false));
}
