const std = @import("std");
const ArrayList = std.ArrayList;
const testing = std.testing;

/// Candidates are the strings read from stdin
/// if the filepath matching algorithm is used, then name will be
/// used to store the filename of the path in str.
pub const Candidate = struct {
    str: []const u8,
    name: []const u8 = undefined,
    score: usize = 0,
};

/// read the candidates from the buffer
pub fn collectCandidates(allocator: *std.mem.Allocator, buf: []const u8, delimiter: u8) !ArrayList(Candidate) {
    var candidates = ArrayList(Candidate).init(allocator);

    // find delimiters
    var start: usize = 0;
    for (buf) |char, index| {
        if (char == delimiter) {
            // add to arraylist only if slice is not all delimiters
            if (index - start != 0) {
                try candidates.append(.{ .str = buf[start..index] });
            }
            start = index + 1;
        }
    }
    // catch the end if stdio didn't end in a delimiter
    if (start < buf.len) {
        try candidates.append(.{ .str = buf[start..] });
    }

    return candidates;
}

test "collectCandidates whitespace" {
    var candidates = try collectCandidates(testing.allocator, "first second third fourth", ' ');
    defer candidates.deinit();

    const items = candidates.items;
    try testing.expectEqual(@as(usize, 4), items.len);
    try testing.expectEqualStrings("first", items[0].str);
    try testing.expectEqualStrings("second", items[1].str);
    try testing.expectEqualStrings("third", items[2].str);
    try testing.expectEqualStrings("fourth", items[3].str);
}

test "collectCandidates newline" {
    var candidates = try collectCandidates(testing.allocator, "first\nsecond\nthird\nfourth", '\n');
    defer candidates.deinit();

    const items = candidates.items;
    try testing.expectEqual(@as(usize, 4), items.len);
    try testing.expectEqualStrings("first", items[0].str);
    try testing.expectEqualStrings("second", items[1].str);
    try testing.expectEqualStrings("third", items[2].str);
    try testing.expectEqualStrings("fourth", items[3].str);
}

test "collectCandidates whitespace" {
    var candidates = try collectCandidates(testing.allocator, "   first second   third fourth   ", ' ');
    defer candidates.deinit();

    const items = candidates.items;
    try testing.expectEqual(@as(usize, 4), items.len);
    try testing.expectEqualStrings("first", items[0].str);
    try testing.expectEqualStrings("second", items[1].str);
    try testing.expectEqualStrings("third", items[2].str);
    try testing.expectEqualStrings("fourth", items[3].str);
}

pub fn filter(allocator: *std.mem.Allocator, candidates: []Candidate, query: []const u8) !ArrayList(Candidate) {
    var filtered = ArrayList(Candidate).init(allocator);

    for (candidates) |candidate, index| {
        if (query.len == 0 or match(candidate.str, query)) {
            try filtered.append(candidate);
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
    var candidates = [_][]const u8{ "abc", "xyz", "abcdef" };

    // match all strings containing "abc"
    var filtered = try filter(testing.allocator, candidates[0..], "abc");
    defer filtered.deinit();

    var expected = [_][]const u8{ "abc", "abcdef" };
    try testing.expectEqualSlices([]const u8, expected[0..], filtered.items);
}
