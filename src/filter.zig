const std = @import("std");
const ArrayList = std.ArrayList;
const testing = std.testing;

/// Candidates are the strings read from stdin
/// if the filepath matching algorithm is used, then name will be
/// used to store the filename of the path in str.
pub const Candidate = struct {
    str: []const u8,
    name: ?[]const u8 = null,
    rank: usize = 0,
    range: ?struct {
        start: usize = 0,
        end: usize = 0,
    } = null,
};

pub fn contains(str: []const u8, byte: u8) bool {
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
pub fn collectCandidates(allocator: std.mem.Allocator, buf: []const u8, delimiter: u8) ![]Candidate {
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
    // const end = candidates.items.len - 1;
    // const filename_match = isPath(candidates.items[0].str) or isPath(candidates.items[end].str) or isPath(candidates.items[end / 2].str);
    const filename_match = true;

    if (filename_match) {
        for (candidates.items) |*candidate| {
            candidate.name = std.fs.path.basename(candidate.str);
        }
    }

    return candidates.toOwnedSlice();
}

test "collectCandidates whitespace" {
    var candidates = try collectCandidates(testing.allocator, "first second third fourth", ' ');
    defer testing.allocator.free(candidates);

    try testing.expectEqual(@as(usize, 4), candidates.len);
    try testing.expectEqualStrings("first", candidates[0].str);
    try testing.expectEqualStrings("second", candidates[1].str);
    try testing.expectEqualStrings("third", candidates[2].str);
    try testing.expectEqualStrings("fourth", candidates[3].str);
}

test "collectCandidates newline" {
    var candidates = try collectCandidates(testing.allocator, "first\nsecond\nthird\nfourth", '\n');
    defer testing.allocator.free(candidates);

    try testing.expectEqual(@as(usize, 4), candidates.len);
    try testing.expectEqualStrings("first", candidates[0].str);
    try testing.expectEqualStrings("second", candidates[1].str);
    try testing.expectEqualStrings("third", candidates[2].str);
    try testing.expectEqualStrings("fourth", candidates[3].str);
}

test "collectCandidates excess whitespace" {
    var candidates = try collectCandidates(testing.allocator, "   first second   third fourth   ", ' ');
    defer testing.allocator.free(candidates);

    try testing.expectEqual(@as(usize, 4), candidates.len);
    try testing.expectEqualStrings("first", candidates[0].str);
    try testing.expectEqualStrings("second", candidates[1].str);
    try testing.expectEqualStrings("third", candidates[2].str);
    try testing.expectEqualStrings("fourth", candidates[3].str);
}

fn hasUpper(query: []const u8) bool {
    for (query) |*c| {
        if (std.ascii.isUpper(c.*)) return true;
    }
    return false;
}

/// rank each candidate against the query
///
/// returns a sorted slice of Candidates that match the query ready for display
/// in a tui or output to stdout
pub fn rankCandidates(allocator: std.mem.Allocator, candidates: []Candidate, query: []const u8) ![]Candidate {
    var ranked = ArrayList(Candidate).init(allocator);
    const smart_case = !hasUpper(query);

    if (query.len == 0) {
        for (candidates) |candidate| {
            try ranked.append(candidate);
        }
        return ranked.toOwnedSlice();
    }

    var query_tokens = try splitQuery(allocator, query);
    defer allocator.free(query_tokens);
    for (candidates) |candidate| {
        var c = candidate;
        if (rankCandidate(&c, query_tokens, smart_case)) {
            try ranked.append(c);
        }
    }

    std.sort.sort(Candidate, ranked.items, {}, sort);

    return ranked.toOwnedSlice();
}

/// split the query on spaces and return a slice of query tokens
fn splitQuery(allocator: std.mem.Allocator, query: []const u8) ![][]const u8 {
    var tokens = ArrayList([]const u8).init(allocator);

    var it = std.mem.tokenize(u8, query, " ");
    while (it.next()) |token| {
        try tokens.append(token);
    }

    return tokens.toOwnedSlice();
}

const indexOfCaseSensitive = std.mem.indexOfScalarPos;

fn indexOf(comptime T: type, slice: []const T, start_index: usize, value: T) ?usize {
    var i: usize = start_index;
    while (i < slice.len) : (i += 1) {
        if (std.ascii.toLower(slice[i]) == value) return i;
    }
    return null;
}

const IndexIterator = struct {
    str: []const u8,
    char: u8,
    index: usize = 0,
    smart_case: bool,

    pub fn init(str: []const u8, char: u8, smart_case: bool) @This() {
        return .{ .str = str, .char = char, .smart_case = smart_case };
    }

    pub fn next(self: *@This()) ?usize {
        const index = if (self.smart_case) indexOf(u8, self.str, self.index, self.char) else indexOfCaseSensitive(u8, self.str, self.index, self.char);
        if (index) |i| self.index = i + 1;
        return index;
    }
};

/// rank a candidate against the given query tokens
///
/// algorithm inspired by https://github.com/garybernhardt/selecta
fn rankCandidate(candidate: *Candidate, query_tokens: [][]const u8, smart_case: bool) bool {
    candidate.rank = 0;

    // the candidate must contain all of the characters (in order) in each token.
    // each tokens rank is summed. if any token does not match the candidate is ignored
    for (query_tokens) |token| {
        if (rankToken(candidate, token, smart_case)) |r| {
            candidate.rank += r;
        } else return false;
    }

    // all tokens matched and the best ranks for each tokens are summed
    return true;
}

fn rankToken(candidate: *Candidate, token: []const u8, smart_case: bool) ?usize {
    // iterate over the indexes where the first char of the token matches
    var best_rank: ?usize = null;
    var it = IndexIterator.init(candidate.name.?, token[0], smart_case);

    // TODO: rank better for name matches
    const offs = candidate.str.len - candidate.name.?.len;
    while (it.next()) |start_index| {
        if (scanToEnd(candidate.name.?, token[1..], start_index, smart_case)) |match| {
            if (best_rank == null or match.rank < best_rank.?) {
                best_rank = match.rank -| 2;
                candidate.range = .{ .start = match.start + offs, .end = match.end + offs };
            }
        } else break;
    }

    // retry on the full string
    if (best_rank == null) {
        it = IndexIterator.init(candidate.str, token[0], smart_case);
        while (it.next()) |start_index| {
            if (scanToEnd(candidate.str, token[1..], start_index, smart_case)) |match| {
                if (best_rank == null or match.rank < best_rank.?) {
                    best_rank = match.rank;
                    candidate.range = .{ .start = match.start, .end = match.end };
                }
            } else break;
        }
    }

    return best_rank;
}

const Match = struct {
    rank: usize,
    start: usize,
    end: usize,
};

/// this is the core of the ranking algorithm. special precedence is given to
/// filenames. if a match is found on a filename the candidate is ranked higher
fn scanToEnd(str: []const u8, token: []const u8, start_index: usize, smart_case: bool) ?Match {
    var match: Match = .{ .rank = 1, .start = start_index, .end = 0 };
    var last_index = start_index;
    var last_sequential = false;

    for (token) |c| {
        const index = if (smart_case) indexOf(u8, str, last_index, c) else indexOfCaseSensitive(u8, str, last_index, c);
        if (index == null) return null;

        if (index.? == last_index + 1) {
            // sequential matches only count the first character
            if (!last_sequential) {
                last_sequential = true;
                match.rank += 1;
            }
        } else {
            // normal match
            last_sequential = false;
            match.rank += index.? - last_index;
        }

        last_index = index.?;
    }

    match.end = last_index;
    return match;
}

fn sort(_: void, a: Candidate, b: Candidate) bool {
    // first by rank
    if (a.rank < b.rank) return true;
    if (a.rank > b.rank) return false;

    // then by length
    if (a.str.len < b.str.len) return true;
    if (a.str.len > b.str.len) return false;

    // then alphabetically
    for (a.str) |c, i| {
        if (c < b.str[i]) return true;
        if (c > b.str[i]) return false;
    }
    return false;
}
