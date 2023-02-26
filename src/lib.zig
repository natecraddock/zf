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

/// compute matching ranges given a string and a slice of tokens
pub fn highlight(
    str: []const u8,
    tokens: []const []const u8,
    case_sensitive: bool,
    plain: bool,
    matches: []usize,
) []usize {
    const filename = if (plain) null else std.fs.path.basename(str);

    var index: usize = 0;
    for (tokens) |token| {
        const matched = filter.highlightToken(str, filename, token, case_sensitive, matches[index..]);
        index += matched.len;
    }

    return matches[0..index];
}

/// compute matching ranges given a string and a single token
pub fn highlightToken(
    str: []const u8,
    filename: ?[]const u8,
    token: []const u8,
    case_sensitive: bool,
    matches: []usize,
) []const usize {
    return filter.highlightToken(str, filename, token, case_sensitive, matches);
}

test "highlight library interface" {
    var matches_buf: [128]usize = undefined;

    try testing.expectEqualSlices(usize, &.{ 0, 5 }, highlight("abcdef", &.{ "a", "f" }, false, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{ 0, 5 }, highlight("abcdeF", &.{ "a", "F" }, true, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{ 2, 3, 4, 5, 10, 11, 12, 13 }, highlight("a/path/to/file", &.{ "path", "file" }, false, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{ 4, 5, 6, 7, 8, 9, 10 }, highlight("lib/ziglyph/zig.mod", &.{"ziglyph"}, false, false, &matches_buf));

    try testing.expectEqualSlices(usize, &.{0}, highlightToken("abcdef", null, "a", false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{5}, highlightToken("abcdeF", null, "F", true, &matches_buf));
    try testing.expectEqualSlices(usize, &.{ 10, 11, 12, 13 }, highlightToken("a/path/to/file", "file", "file", false, &matches_buf));

    // highlights with basename trailing slashes
    try testing.expectEqualSlices(usize, &.{0}, highlightToken("s/", "s", "s", false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{ 20, 21, 22, 23 }, highlightToken("/this/is/path/not/a/file/", "file", "file", false, &matches_buf));

    // disconnected highlights
    try testing.expectEqualSlices(usize, &.{ 0, 2, 3 }, highlight("ababab", &.{"aab"}, false, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{ 6, 8, 9 }, highlight("abbbbbabab", &.{"aab"}, false, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{ 0, 2, 6 }, highlight("abcdefg", &.{"acg"}, false, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{ 2, 3, 4, 5, 9, 10 }, highlight("__init__.py", &.{"initpy"}, false, false, &matches_buf));

    // small buffer to ensure highlighting doesn't go out of range when the tokens overflow
    var small_buf: [4]usize = undefined;
    try testing.expectEqualSlices(usize, &.{0, 1, 2, 3}, highlight("abcd", &.{"ab", "cd", "abcd"}, false, false, &small_buf));
    try testing.expectEqualSlices(usize, &.{0, 1, 2, 1}, highlight("wxyz", &.{"wxy", "xyz"}, false, false, &small_buf));
}
