const std = @import("std");
const ArrayList = std.ArrayList;
const testing = std.testing;

/// Candidates are the strings read from stdin
/// if the filepath matching algorithm is used, then name will be
/// used to store the filename of the path in str.
pub const Candidate = struct {
    str: []const u8,
    name: ?[]const u8 = null,
    rank: f64 = 0,
    ranges: ?[]Range = null,
};

pub const Range = struct {
    start: usize = 0,
    end: usize = 0,
};

/// read the candidates from the buffer
pub fn collectCandidates(allocator: std.mem.Allocator, buf: []const u8, delimiter: u8, plain: bool) ![]Candidate {
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

    // extract filepaths
    if (!plain) {
        for (candidates.items) |*candidate| {
            candidate.name = std.fs.path.basename(candidate.str);
        }
    }

    return candidates.toOwnedSlice();
}

test "collectCandidates whitespace" {
    var candidates = try collectCandidates(testing.allocator, "first second third fourth", ' ', false);
    defer testing.allocator.free(candidates);

    try testing.expectEqual(@as(usize, 4), candidates.len);
    try testing.expectEqualStrings("first", candidates[0].str);
    try testing.expectEqualStrings("second", candidates[1].str);
    try testing.expectEqualStrings("third", candidates[2].str);
    try testing.expectEqualStrings("fourth", candidates[3].str);
}

test "collectCandidates newline" {
    var candidates = try collectCandidates(testing.allocator, "first\nsecond\nthird\nfourth", '\n', false);
    defer testing.allocator.free(candidates);

    try testing.expectEqual(@as(usize, 4), candidates.len);
    try testing.expectEqualStrings("first", candidates[0].str);
    try testing.expectEqualStrings("second", candidates[1].str);
    try testing.expectEqualStrings("third", candidates[2].str);
    try testing.expectEqualStrings("fourth", candidates[3].str);
}

test "collectCandidates excess whitespace" {
    var candidates = try collectCandidates(testing.allocator, "   first second   third fourth   ", ' ', false);
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
pub fn rankCandidates(
    allocator: std.mem.Allocator,
    candidates: []Candidate,
    query: []const u8,
    keep_order: bool,
) ![]Candidate {
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
        c.ranges = try allocator.alloc(Range, query_tokens.len);
        if (rankCandidate(&c, query_tokens, smart_case)) {
            try ranked.append(c);
        }
    }

    if (!keep_order) {
        std.sort.sort(Candidate, ranked.items, {}, sort);
    }

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

inline fn inRange(a: Range, b: Range) bool {
    return b.start >= a.start and b.end <= a.end;
}

/// rank a candidate against the given query tokens
///
/// algorithm inspired by https://github.com/garybernhardt/selecta
fn rankCandidate(candidate: *Candidate, query_tokens: [][]const u8, smart_case: bool) bool {
    candidate.rank = 0;

    // the candidate must contain all of the characters (in order) in each token.
    // each tokens rank is summed. if any token does not match the candidate is ignored
    var matched_filename = false;
    for (query_tokens) |token, i| {
        if (rankToken(candidate.str, candidate.name, &candidate.ranges.?[i], token, &matched_filename, smart_case)) |r| {
            candidate.rank += r;

            // penalty for a match within the same range as the previous match
            if (i > 0 and inRange(candidate.ranges.?[i - 1], candidate.ranges.?[i])) candidate.rank += 1;
        } else return false;
    }

    // all tokens matched and the best ranks for each tokens are summed
    return true;
}

pub fn rankToken(
    str: []const u8,
    name: ?[]const u8,
    range: *Range,
    token: []const u8,
    matched_filename: *bool,
    smart_case: bool,
) ?f64 {
    // iterate over the indexes where the first char of the token matches
    var best_rank: ?f64 = null;
    var it = IndexIterator.init(name.?, token[0], smart_case);

    if (!matched_filename.*) {
        const offs = str.len - name.?.len;
        while (it.next()) |start_index| {
            if (scanToEnd(name.?, token[1..], start_index, smart_case)) |match| {
                if (best_rank == null or match.rank < best_rank.?) {
                    best_rank = match.rank;
                    range.* = .{ .start = match.start + offs, .end = match.end + offs };
                }
            } else break;
        }
    }

    if (best_rank != null) {
        matched_filename.* = true;

        // was a filename match, give priority
        best_rank.? /= 2.0;

        // how much of the token matched the filename?
        if (token.len == name.?.len) {
            best_rank.? /= 2.0;
        } else {
            const coverage = 1.0 - (@intToFloat(f64, token.len) / @intToFloat(f64, name.?.len));
            best_rank.? *= coverage;
        }
    } else {
        // retry on the full string
        it = IndexIterator.init(str, token[0], smart_case);
        while (it.next()) |start_index| {
            if (scanToEnd(str, token[1..], start_index, smart_case)) |match| {
                if (best_rank == null or match.rank < best_rank.?) {
                    best_rank = match.rank;
                    range.* = .{ .start = match.start, .end = match.end };
                }
            } else break;
        }
    }

    return best_rank;
}

const Match = struct {
    rank: f64,
    start: usize,
    end: usize,
};

inline fn isStartOfWord(byte: u8) bool {
    return switch (byte) {
        std.fs.path.sep, '_', '-', '.', ' ' => true,
        else => false,
    };
}

/// this is the core of the ranking algorithm. special precedence is given to
/// filenames. if a match is found on a filename the candidate is ranked higher
fn scanToEnd(str: []const u8, token: []const u8, start_index: usize, smart_case: bool) ?Match {
    var match: Match = .{ .rank = 1, .start = start_index, .end = 0 };
    var last_index = start_index;
    var last_sequential = false;

    // penalty for not starting on a word boundary
    if (start_index > 0 and !isStartOfWord(str[start_index - 1])) {
        match.rank += 2.0;
    }

    for (token) |c| {
        const index = if (smart_case) indexOf(u8, str, last_index + 1, c) else indexOfCaseSensitive(u8, str, last_index + 1, c);
        if (index == null) return null;

        if (index.? == last_index + 1) {
            // sequential matches only count the first character
            if (!last_sequential) {
                last_sequential = true;
                match.rank += 1.0;
            }
        } else {
            // penalty for not starting on a word boundary
            if (!isStartOfWord(str[index.? - 1])) {
                match.rank += 2.0;
            }

            // normal match
            last_sequential = false;
            match.rank += @intToFloat(f64, index.? - last_index);
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
