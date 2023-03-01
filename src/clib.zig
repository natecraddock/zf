const filter = @import("filter.zig");
const std = @import("std");
const testing = std.testing;

/// rank a given string against a slice of tokens
export fn rank(
    str: [*:0]const u8,
    tokens: [*]const [*:0]const u8,
    num_tokens: usize,
    case_sensitive: bool,
    plain: bool,
) f64 {
    const string = std.mem.span(str);
    const filename = if (plain) null else std.fs.path.basename(string);

    var total_rank: f64 = 0;
    var index: usize = 0;
    while (index < num_tokens) : (index += 1) {
        const token = std.mem.span(tokens[index]);
        if (filter.rankToken(string, filename, token, case_sensitive)) |r| {
            total_rank += r;
        } else return -1.0;
    }
    return total_rank;
}

/// rank a given string against a single token
export fn rankToken(
    str: [*:0]const u8,
    filename: ?[*:0]const u8,
    token: [*:0]const u8,
    case_sensitive: bool,
) f64 {
    const string = std.mem.span(str);
    const name = if (filename != null) std.mem.span(filename) else null;
    const tok = std.mem.span(token);
    if (filter.rankToken(string, name, tok, case_sensitive)) |r| {
        return r;
    } else return -1.0;
}

test "rank exported C library interface" {
    {
        const tokens: [2][*:0]const u8 = .{ "a", "z" };
        try testing.expect(rank("abcdefg", &tokens, 2, false, false) == -1);
    }
    {
        const tokens: [2][*:0]const u8 = .{ "a", "b" };
        try testing.expect(rank("abcdefg", &tokens, 2, false, false) != -1);
    }
    {
        const tokens: [2][*:0]const u8 = .{ "a", "B" };
        try testing.expect(rank("abcdefg", &tokens, 2, true, false) == -1);
    }
    {
        const tokens: [2][*:0]const u8 = .{ "a", "B" };
        try testing.expect(rank("aBcdefg", &tokens, 2, true, false) != -1);
    }
    {
        const tokens: [1][*:0]const u8 = .{"zig"};
        try testing.expect(rank("a/path/to/file", &tokens, 2, false, false) == -1);
    }
    {
        const tokens: [2][*:0]const u8 = .{ "path", "file" };
        try testing.expect(rank("a/path/to/file", &tokens, 2, false, false) != -1);
    }

    try testing.expect(rankToken("abcdefg", null, "a", false) != -1);
    try testing.expect(rankToken("abcdefg", null, "z", false) == -1);
    try testing.expect(rankToken("abcdefG", null, "G", true) != -1);
    try testing.expect(rankToken("abcdefg", null, "A", true) == -1);
    try testing.expect(rankToken("a/path/to/file", "file", "file", false) != -1);
    try testing.expect(rankToken("a/path/to/file", "file", "zig", false) == -1);

    // zero length strings and tokens
    {
        const tokens: [1][*:0]const u8 = .{ "a" };
        try testing.expect(rank("", &tokens, 1, false, false) == -1);
    }
    try testing.expect(rankToken("", null, "a", false) == -1);
    {
        const tokens: [1][*:0]const u8 = .{ "" };
        try testing.expect(rank("a", &tokens, 1, false, false) == -1);
    }
    try testing.expect(rankToken("a", null, "", false) == -1);
}

export fn highlight(
    str: [*:0]const u8,
    tokens: [*]const [*:0]const u8,
    tokens_len: usize,
    case_sensitive: bool,
    plain: bool,
    matches: [*]usize,
    matches_len: usize,
) usize {
    const string = std.mem.span(str);
    const filename = if (plain) null else std.fs.path.basename(string);
    var matches_slice = matches[0..matches_len];

    var index: usize = 0;
    var token_index: usize = 0;
    while (token_index < tokens_len) : (token_index += 1) {
        const token = std.mem.span(tokens[token_index]);
        const matched = filter.highlightToken(string, filename, token, case_sensitive, matches_slice[index..]);
        index += matched.len;
    }

    return index;
}

export fn highlightToken(
    str: [*:0]const u8,
    filename: ?[*:0]const u8,
    token: [*:0]const u8,
    case_sensitive: bool,
    matches: [*]usize,
    matches_len: usize,
) usize {
    const string = std.mem.span(str);
    const name = if (filename != null) std.mem.span(filename) else null;
    const tok = std.mem.span(token);
    var matches_slice = matches[0..matches_len];
    const matched = filter.highlightToken(string, name, tok, case_sensitive, matches_slice);
    return matched.len;
}

fn testHighlight(
    expectedMatches: []const usize,
    str: [*:0]const u8,
    tokens: []const [*:0]const u8,
    case_sensitive: bool,
    plain: bool,
    matches_buf: []usize,
) !void {
    const len = highlight(str, tokens.ptr, tokens.len, case_sensitive, plain, matches_buf.ptr, matches_buf.len);
    try testing.expectEqualSlices(usize, expectedMatches, matches_buf[0..len]);
}

test "highlight exported C library interface" {
    var matches_buf: [128]usize = undefined;

    try testHighlight(&.{ 0, 5 }, "abcdef", &.{ "a", "f" }, false, false, &matches_buf);
    try testHighlight(&.{ 0, 5 }, "abcdeF", &.{ "a", "F" }, true, false, &matches_buf);
    try testHighlight(&.{ 2, 3, 4, 5, 10, 11, 12, 13 }, "a/path/to/file", &.{ "path", "file" }, false, false, &matches_buf);

    var len = highlightToken("abcdef", null, "a", false, &matches_buf, matches_buf.len);
    try testing.expectEqualSlices(usize, &.{0}, matches_buf[0..len]);
    len = highlightToken("abcdeF", null, "F", true, &matches_buf, matches_buf.len);
    try testing.expectEqualSlices(usize, &.{5}, matches_buf[0..len]);
    len = highlightToken("a/path/to/file", "file", "file", false, &matches_buf, matches_buf.len);
    try testing.expectEqualSlices(usize, &.{ 10, 11, 12, 13 }, matches_buf[0..len]);

    // highlights with basename trailing slashes
    len = highlightToken("s/", "s", "s", false, &matches_buf, matches_buf.len);
    try testing.expectEqualSlices(usize, &.{0}, matches_buf[0..len]);
    len = highlightToken("/this/is/path/not/a/file/", "file", "file", false, &matches_buf, matches_buf.len);
    try testing.expectEqualSlices(usize, &.{ 20, 21, 22, 23 }, matches_buf[0..len]);

    // disconnected highlights
    try testHighlight(&.{ 0, 2, 3 }, "ababab", &.{"aab"}, false, false, &matches_buf);
    try testHighlight(&.{ 6, 8, 9 }, "abbbbbabab", &.{"aab"}, false, false, &matches_buf);
    try testHighlight(&.{ 0, 2, 6 }, "abcdefg", &.{"acg"}, false, false, &matches_buf);
    try testHighlight(&.{ 2, 3, 4, 5, 9, 10 }, "__init__.py", &.{"initpy"}, false, false, &matches_buf);

    // small buffer to ensure highlighting doesn't go out of range when the tokens overflow
    var small_buf: [4]usize = undefined;
    try testHighlight(&.{0, 1, 2, 3}, "abcd", &.{"ab", "cd", "abcd"}, false, false, &small_buf);
    try testHighlight(&.{0, 1, 2, 1}, "wxyz", &.{"wxy", "xyz"}, false, false, &small_buf);

    // zero length strings and tokens
    try testHighlight(&.{}, "", &.{ "a" }, false, false, &matches_buf);
    len = highlightToken("", null, "a", false, &matches_buf, matches_buf.len);
    try testing.expectEqualSlices(usize, &.{}, matches_buf[0..len]);
    try testHighlight(&.{}, "a", &.{ "" }, false, false, &matches_buf);
    len = highlightToken("a", null, "", false, &matches_buf, matches_buf.len);
    try testing.expectEqualSlices(usize, &.{}, matches_buf[0..len]);
}
