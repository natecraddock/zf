const filter = @import("filter.zig");
const std = @import("std");
const testing = std.testing;

/// rank a given string against a slice of tokens
pub fn rank(
    str: []const u8,
    tokens: []const []const u8,
    case_sensitive: bool,
    plain: bool,
) ?f64 {
    return filter.rankCandidate(str, tokens, case_sensitive, plain);
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
    try testing.expect(rank("abcdefg", &.{ "a", "z" }, false, false) == null);
    try testing.expect(rank("abcdefg", &.{ "a", "b" }, false, false) != null);
    try testing.expect(rank("abcdefg", &.{ "a", "B" }, true, false) == null);
    try testing.expect(rank("aBcdefg", &.{ "a", "B" }, true, false) != null);
    try testing.expect(rank("a/path/to/file", &.{"zig"}, false, false) == null);
    try testing.expect(rank("a/path/to/file", &.{ "path", "file" }, false, false) != null);

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
    ranges: []Range,
    tokens: []const []const u8,
    case_sensitive: bool,
    plain: bool,
) void {
    const filename = if (plain) null else std.fs.path.basename(str);
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
    tokens: []const []const u8,
    case_sensitive: bool,
    plain: bool,
) !void {
    var ranges = try testing.allocator.alloc(Range, tokens.len);
    defer testing.allocator.free(ranges);
    highlight(str, ranges, tokens, case_sensitive, plain);
    try testing.expectEqualSlices(Range, expectedRanges, ranges);
}

test "highlight library interface" {
    try testHighlight(&.{ .{ .start = 0, .end = 0 }, .{ .start = 5, .end = 5 } }, "abcdef", &.{ "a", "f" }, false, false);
    try testHighlight(&.{ .{ .start = 0, .end = 0 }, .{ .start = 5, .end = 5 } }, "abcdeF", &.{ "a", "F" }, true, false);
    try testHighlight(&.{ .{ .start = 2, .end = 5 }, .{ .start = 10, .end = 13 } }, "a/path/to/file", &.{ "path", "file" }, false, false);

    try testing.expectEqual(Range{ .start = 0, .end = 0 }, highlightToken("abcdef", null, "a", false));
    try testing.expectEqual(Range{ .start = 5, .end = 5 }, highlightToken("abcdeF", null, "F", true));
    try testing.expectEqual(Range{ .start = 10, .end = 13 }, highlightToken("a/path/to/file", "file", "file", false));

    // highlights with basename trailing slashes
    try testing.expectEqual(Range{ .start = 0, .end = 0 }, highlightToken("s/", "s", "s", false));
    try testing.expectEqual(Range{ .start = 20, .end = 23 }, highlightToken("/this/is/path/not/a/file/", "file", "file", false));
}
