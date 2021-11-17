const std = @import("std");
const ArrayList = std.ArrayList;
const testing = std.testing;

/// Candidates are the strings read from stdin
/// if the filepath matching algorithm is used, then name will be
/// used to store the filename of the path in str.
pub const Candidate = struct {
    str: []const u8,
    name: ?[]const u8 = null,
    score: usize = 0,
};

fn contains(str: []const u8, byte: u8) bool {
    for (str) |b| {
        if (b == byte) return true;
    }
    return false;
}

/// if a string contains either a separator or a . character, then we assume it is a filepath
fn isPath(str: []const u8) bool {
    if (contains(str, std.fs.path.sep)) return true;
    if (contains(str, '.')) return true;
    return false;
}

test "is path" {
    try testing.expect(isPath("/dev/null"));
    try testing.expect(isPath("main.zig"));
    try testing.expect(isPath("src/tty.zig"));
    try testing.expect(isPath("a/b/c"));

    try testing.expect(!isPath("a"));
    try testing.expect(!isPath("abcdefghijklmnopqrstuvwxyz"));

    // the heuristics are not perfect! not all "files" will be considered as a file
    try testing.expect(!isPath("Makefile"));
}

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

    // determine if these candidates are filepaths
    const end = candidates.items.len - 1;
    const filename_match = isPath(candidates.items[0].str) or isPath(candidates.items[end].str) or isPath(candidates.items[end / 2].str);

    if (filename_match) {
        for (candidates.items) |*candidate| {
            candidate.name = std.fs.path.basename(candidate.str);
        }
    }

    std.sort.sort(Candidate, candidates.items, {}, sort);

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

test "collectCandidates excess whitespace" {
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

    if (query.len == 0) {
        for (candidates) |candidate| {
            try filtered.append(candidate);
        }
        return filtered;
    }

    const filename_match = true;
    if (filename_match) {
        for (candidates) |*candidate| {
            score(candidate, query, true);
            if (candidate.score > 0) try filtered.append(candidate.*);
        }
    } else {
        for (candidates) |*candidate| {
            score(candidate, query, false);
            if (candidate.score > 0) try filtered.append(candidate.*);
        }
    }

    return filtered;
}

/// search for needle in haystack and return length of matching substring
/// returns null if there is no match
fn fuzzyMatch(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len > haystack.len) return null;

    var start: ?usize = null;
    var matches: usize = 0;
    for (haystack) |char, i| {
        if (needle[matches] == char) {
            if (start == null) start = i;
            matches += 1;
        }

        // all chars have matched
        if (matches == needle.len) return i - start.? + 1;
    }

    return null;
}

test "fuzzy match" {
    try testing.expect(fuzzyMatch("abcdefg", "z") == null);
    try testing.expect(fuzzyMatch("a", "xyz") == null);
    try testing.expect(fuzzyMatch("xy", "xyz") == null);

    try testing.expect(fuzzyMatch("abc", "a").? == 1);
    try testing.expect(fuzzyMatch("abc", "abc").? == 3);
    try testing.expect(fuzzyMatch("abc", "ac").? == 3);
    try testing.expect(fuzzyMatch("main.zig", "mi").? == 3);
    try testing.expect(fuzzyMatch("main.zig", "miz").? == 6);
    try testing.expect(fuzzyMatch("main.zig", "mzig").? == 8);
    try testing.expect(fuzzyMatch("main.zig", "zig").? == 3);
}

/// rate how closely the query matches the candidate
fn score(candidate: *Candidate, query: []const u8, comptime filepath: bool) void {
    candidate.score = 0;

    if (filepath) {
        if (fuzzyMatch(candidate.name.?, query)) |s| {
            candidate.score = 1;
            return;
        }
    }

    if (query.len > candidate.str.len) return;

    if (fuzzyMatch(candidate.str, query)) |s| {
        candidate.score = s;
        return;
    }
}

test "simple filter" {
    // var candidates = [_][]const u8{ "abc", "xyz", "abcdef" };

    // // match all strings containing "abc"
    // var filtered = try filter(testing.allocator, candidates[0..], "abc");
    // defer filtered.deinit();

    // var expected = [_][]const u8{ "abc", "abcdef" };
    // try testing.expectEqualSlices([]const u8, expected[0..], filtered.items);
}

pub fn sort(_: void, a: Candidate, b: Candidate) bool {
    if (a.score < b.score) return true;
    if (a.str.len < b.str.len) return true;
    return false;
}
