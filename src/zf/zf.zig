//! zf.zig
//! The zf fuzzy finding algorithm
//! Inspired by https://github.com/garybernhardt/selecta

const filter = @import("filter.zig");
const std = @import("std");
const testing = std.testing;

test {
    _ = @import("clib.zig");
    _ = @import("filter.zig");
}

/// rank a given string against a slice of tokens
pub fn rank(
    str: []const u8,
    tokens: []const []const u8,
    case_sensitive: bool,
    plain: bool,
) ?f64 {
    const filename = if (plain) null else std.fs.path.basename(str);

    // the candidate must contain all of the characters (in order) in each token.
    // each tokens rank is summed. if any token does not match the candidate is ignored
    var sum: f64 = 0;
    for (tokens) |token| {
        const strict_path = !plain and filter.hasSeparator(token);
        if (rankToken(str, filename, token, case_sensitive, strict_path)) |r| {
            sum += r;
        } else return null;
    }

    // all tokens matched and the best ranks for each tokens are summed
    return sum;
}

/// rank a given string against a single token
pub fn rankToken(
    str: []const u8,
    filename: ?[]const u8,
    token: []const u8,
    case_sensitive: bool,
    strict_path: bool,
) ?f64 {
    return filter.rankToken(str, filename, token, case_sensitive, strict_path);
}

test "rank library interface" {
    try testing.expect(rank("abcdefg", &.{ "a", "z" }, false, false) == null);
    try testing.expect(rank("abcdefg", &.{ "a", "b" }, false, false) != null);
    try testing.expect(rank("abcdefg", &.{ "a", "B" }, true, false) == null);
    try testing.expect(rank("aBcdefg", &.{ "a", "B" }, true, false) != null);
    try testing.expect(rank("a/path/to/file", &.{"zig"}, false, false) == null);
    try testing.expect(rank("a/path/to/file", &.{ "path", "file" }, false, false) != null);

    try testing.expect(rankToken("abcdefg", null, "a", false, false) != null);
    try testing.expect(rankToken("abcdefg", null, "z", false, false) == null);
    try testing.expect(rankToken("abcdefG", null, "G", true, false) != null);
    try testing.expect(rankToken("abcdefg", null, "A", true, false) == null);
    try testing.expect(rankToken("a/path/to/file", "file", "file", false, false) != null);
    try testing.expect(rankToken("a/path/to/file", "file", "zig", false, false) == null);

    // zero length strings and tokens
    try testing.expect(rank("", &.{"a"}, false, false) == null);
    try testing.expect(rankToken("", null, "a", false, false) == null);
    try testing.expect(rank("a", &.{""}, false, false) == null);
    try testing.expect(rankToken("a", null, "", false, false) == null);
}

// Maybe all that needs to be done is to sort the highlight integers? That would probably save some work in implementation
// Or maybe could sort and then make ranges out of the pairs? Return a list of ranges?
// for the Zig api that could be reasonable... but the C api maybe not
// sorting as a minimum for sure

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
        const strict_path = !plain and filter.hasSeparator(token);
        const matched = filter.highlightToken(str, filename, token, case_sensitive, strict_path, matches[index..]);
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
    strict_path: bool,
    matches: []usize,
) []const usize {
    return filter.highlightToken(str, filename, token, case_sensitive, strict_path, matches);
}

test "highlight library interface" {
    var matches_buf: [128]usize = undefined;

    try testing.expectEqualSlices(usize, &.{ 0, 5 }, highlight("abcdef", &.{ "a", "f" }, false, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{ 0, 5 }, highlight("abcdeF", &.{ "a", "F" }, true, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{ 2, 3, 4, 5, 10, 11, 12, 13 }, highlight("a/path/to/file", &.{ "path", "file" }, false, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{ 4, 5, 6, 7, 8, 9, 10 }, highlight("lib/ziglyph/zig.mod", &.{"ziglyph"}, false, false, &matches_buf));

    try testing.expectEqualSlices(usize, &.{0}, highlightToken("abcdef", null, "a", false, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{5}, highlightToken("abcdeF", null, "F", true, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{ 10, 11, 12, 13 }, highlightToken("a/path/to/file", "file", "file", false, false, &matches_buf));

    // highlights with basename trailing slashes
    try testing.expectEqualSlices(usize, &.{0}, highlightToken("s/", "s", "s", false, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{ 20, 21, 22, 23 }, highlightToken("/this/is/path/not/a/file/", "file", "file", false, false, &matches_buf));

    // disconnected highlights
    try testing.expectEqualSlices(usize, &.{ 0, 2, 3 }, highlight("ababab", &.{"aab"}, false, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{ 6, 8, 9 }, highlight("abbbbbabab", &.{"aab"}, false, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{ 0, 2, 6 }, highlight("abcdefg", &.{"acg"}, false, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{ 2, 3, 4, 5, 9, 10 }, highlight("__init__.py", &.{"initpy"}, false, false, &matches_buf));

    // small buffer to ensure highlighting doesn't go out of range when the tokens overflow
    var small_buf: [4]usize = undefined;
    try testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3 }, highlight("abcd", &.{ "ab", "cd", "abcd" }, false, false, &small_buf));
    try testing.expectEqualSlices(usize, &.{ 0, 1, 2, 1 }, highlight("wxyz", &.{ "wxy", "xyz" }, false, false, &small_buf));

    // zero length strings and tokens
    try testing.expectEqualSlices(usize, &.{}, highlight("", &.{"a"}, false, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{}, highlightToken("", null, "a", false, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{}, highlight("a", &.{""}, false, false, &matches_buf));
    try testing.expectEqualSlices(usize, &.{}, highlightToken("a", null, "", false, false, &matches_buf));
}
