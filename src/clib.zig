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
}

const Range = filter.Range;

export fn highlight(
    str: [*:0]const u8,
    ranges: [*]Range,
    tokens: [*]const [*:0]const u8,
    num: usize,
    case_sensitive: bool,
    plain: bool,
) void {
    const string = std.mem.span(str);
    const filename = if (plain) null else std.fs.path.basename(string);

    var index: usize = 0;
    while (index < num) : (index += 1) {
        const token = std.mem.span(tokens[index]);
        ranges[index] = filter.highlightToken(string, filename, token, case_sensitive);
    }
}

export fn highlightToken(
    str: [*:0]const u8,
    filename: ?[*:0]const u8,
    token: [*:0]const u8,
    case_sensitive: bool,
) Range {
    const string = std.mem.span(str);
    const name = if (filename != null) std.mem.span(filename) else null;
    const tok = std.mem.span(token);
    return filter.highlightToken(string, name, tok, case_sensitive);
}

fn testHighlight(
    expectedRanges: []const Range,
    str: [*:0]const u8,
    tokens: []const [*:0]const u8,
    case_sensitive: bool,
    plain: bool,
) !void {
    var ranges = try testing.allocator.alloc(Range, tokens.len);
    defer testing.allocator.free(ranges);
    highlight(str, ranges.ptr, tokens.ptr, ranges.len, case_sensitive, plain);
    try testing.expectEqualSlices(Range, expectedRanges, ranges);
}

test "highlight exported C library interface" {
    try testHighlight(&.{ .{ .start = 0, .end = 0 }, .{ .start = 5, .end = 5 } }, "abcdef", &.{ "a", "f" }, false, false);
    try testHighlight(&.{ .{ .start = 0, .end = 0 }, .{ .start = 5, .end = 5 } }, "abcdeF", &.{ "a", "F" }, true, false);
    try testHighlight(&.{ .{ .start = 2, .end = 5 }, .{ .start = 10, .end = 13 } }, "a/path/to/file", &.{ "path", "file" }, false, false);

    try testing.expectEqual(Range{ .start = 0, .end = 0 }, highlightToken("abcdef", null, "a", false));
    try testing.expectEqual(Range{ .start = 5, .end = 5 }, highlightToken("abcdeF", null, "F", true));
    try testing.expectEqual(Range{ .start = 10, .end = 13 }, highlightToken("a/path/to/file", "file", "file", false));
}
