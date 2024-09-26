const std = @import("std");
const testing = std.testing;

const sep = std.fs.path.sep;

fn indexOf(
    comptime T: type,
    slice: []const T,
    start_index: usize,
    value: T,
    comptime case_sensitive: bool,
) ?usize {
    var i: usize = start_index;
    while (i < slice.len) : (i += 1) {
        if (case_sensitive) {
            if (slice[i] == value) return i;
        } else {
            if (std.ascii.toLower(slice[i]) == value) return i;
        }
    }
    return null;
}

const IndexIterator = struct {
    str: []const u8,
    char: u8,
    index: usize = 0,
    case_sensitive: bool,

    pub fn init(str: []const u8, char: u8, case_sensitive: bool) @This() {
        return .{ .str = str, .char = char, .case_sensitive = case_sensitive };
    }

    pub fn next(self: *@This()) ?usize {
        const index = if (self.case_sensitive)
            indexOf(u8, self.str, self.index, self.char, true)
        else
            indexOf(u8, self.str, self.index, self.char, false);

        if (index) |i| self.index = i + 1;
        return index;
    }
};

pub fn hasSeparator(str: []const u8) bool {
    for (str) |byte| {
        if (byte == sep) return true;
    }
    return false;
}

const PathIterator = struct {
    str: []const u8,
    index: usize = 0,

    pub fn init(str: []const u8) PathIterator {
        return .{ .str = str };
    }

    pub fn next(iter: *PathIterator) ?[]const u8 {
        if (iter.index >= iter.str.len) return null;

        const start = iter.index;
        if (iter.str[iter.index] == sep) {
            iter.index += 1;
            return iter.str[start..iter.index];
        }

        while (iter.index < iter.str.len) : (iter.index += 1) {
            if (iter.str[iter.index] == sep) {
                return iter.str[start..iter.index];
            }
        }

        return iter.str[start..];
    }
};

test "path iterator" {
    var iter = PathIterator.init("");
    try testing.expect(iter.next() == null);

    iter = PathIterator.init("/");
    try testing.expectEqualStrings("/", iter.next().?);
    try testing.expect(iter.next() == null);

    iter = PathIterator.init("a");
    try testing.expectEqualStrings("a", iter.next().?);
    try testing.expect(iter.next() == null);

    iter = PathIterator.init("/a");
    try testing.expectEqualStrings("/", iter.next().?);
    try testing.expectEqualStrings("a", iter.next().?);
    try testing.expect(iter.next() == null);

    iter = PathIterator.init("a/");
    try testing.expectEqualStrings("a", iter.next().?);
    try testing.expectEqualStrings("/", iter.next().?);
    try testing.expect(iter.next() == null);

    iter = PathIterator.init("a/b/");
    try testing.expectEqualStrings("a", iter.next().?);
    try testing.expectEqualStrings("/", iter.next().?);
    try testing.expectEqualStrings("b", iter.next().?);
    try testing.expectEqualStrings("/", iter.next().?);
    try testing.expect(iter.next() == null);

    iter = PathIterator.init("src/data/b.zig");
    try testing.expectEqualStrings("src", iter.next().?);
    try testing.expectEqualStrings("/", iter.next().?);
    try testing.expectEqualStrings("data", iter.next().?);
    try testing.expectEqualStrings("/", iter.next().?);
    try testing.expectEqualStrings("b.zig", iter.next().?);
    try testing.expect(iter.next() == null);
}

/// Scan left and right for the length of the current path segment
pub fn segmentLen(str: []const u8, index: usize) usize {
    if (str[index] == sep) return 1;

    var start = index;
    var end = index;
    while (start > 0) : (start -= 1) {
        if (str[start - 1] == sep) break;
    }
    while (end < str.len and str[end] != sep) : (end += 1) {}
    return end - start;
}

test "segmentLen" {
    try testing.expectEqual(1, segmentLen("a", 0));
    try testing.expectEqual(1, segmentLen("/a", 1));
    try testing.expectEqual(1, segmentLen("/a/", 1));
    try testing.expectEqual(3, segmentLen("src/main.zig", 0));
    try testing.expectEqual(3, segmentLen("src/main.zig", 2));
    try testing.expectEqual(8, segmentLen("src/main.zig", 5));
    try testing.expectEqual(1, segmentLen("a/b", 1));
}

pub fn rankToken(
    str: []const u8,
    filenameOrNull: ?[]const u8,
    token: []const u8,
    case_sensitive: bool,
    strict_path: bool,
) ?f64 {
    if (str.len == 0 or token.len == 0) return null;

    // iterates over the string performing a match starting at each possible index
    // the best (minimum) overall ranking is kept and returned
    var best_rank: ?f64 = null;

    if (strict_path) {
        var iter = PathIterator.init(token);
        var start: usize = 0;
        while (iter.next()) |segment| {
            var it = IndexIterator.init(str, segment[0], case_sensitive);
            it.index = start;
            while (it.next()) |start_index| {
                if (scanToEnd(str, segment[1..], start_index, 0, null, case_sensitive, strict_path)) |scan| {
                    // how much of the query token segment matched the path segment?
                    // "mod" would match "module" better than "modules" for example
                    const path_segment_len = segmentLen(str, start_index);
                    const coverage = 1.0 - (@as(f64, @floatFromInt(segment.len)) / @as(f64, @floatFromInt(path_segment_len)));
                    const rank = coverage * scan.rank;

                    if (best_rank == null) {
                        best_rank = rank;
                    } else best_rank = best_rank.? + rank;

                    start = scan.index;
                    break;
                }
            } else return null;
        }
        return best_rank;
    }

    // perform search on the filename only if requested
    if (filenameOrNull) |filename| {
        var it = IndexIterator.init(filename, token[0], case_sensitive);
        while (it.next()) |start_index| {
            if (scanToEnd(filename, token[1..], start_index, 0, null, case_sensitive, false)) |scan| {
                if (best_rank == null or scan.rank < best_rank.?) best_rank = scan.rank;
            } else break;
        }

        if (best_rank != null) {
            // was a filename match, give priority
            best_rank.? /= 2.0;

            // how much of the token matched the filename?
            if (token.len == filename.len) {
                best_rank.? /= 2.0;
            } else {
                const coverage = 1.0 - (@as(f64, @floatFromInt(token.len)) / @as(f64, @floatFromInt(filename.len)));
                best_rank.? *= coverage;
            }

            return best_rank;
        }
    }

    // perform search on the full string if requested or if no match was found on the filename
    var it = IndexIterator.init(str, token[0], case_sensitive);
    while (it.next()) |start_index| {
        if (scanToEnd(str, token[1..], start_index, 0, null, case_sensitive, false)) |scan| {
            if (best_rank == null or scan.rank < best_rank.?) best_rank = scan.rank;
        } else break;
    }

    return best_rank;
}

test "rankToken" {
    // plain string matching
    try testing.expectEqual(null, rankToken("", null, "", false, false));
    try testing.expectEqual(null, rankToken("", null, "b", false, false));
    try testing.expectEqual(null, rankToken("a", null, "", false, false));
    try testing.expectEqual(null, rankToken("a", null, "b", false, false));
    try testing.expectEqual(null, rankToken("aaa", null, "aab", false, false));
    try testing.expectEqual(null, rankToken("abbba", null, "abab", false, false));

    try testing.expect(rankToken("a", null, "a", false, false) != null);
    try testing.expect(rankToken("abc", null, "abc", false, false) != null);
    try testing.expect(rankToken("aaabbbccc", null, "abc", false, false) != null);
    try testing.expect(rankToken("azbycx", null, "x", false, false) != null);
    try testing.expect(rankToken("azbycx", null, "ax", false, false) != null);
    try testing.expect(rankToken("a", null, "a", false, false) != null);

    // file name matching
    try testing.expectEqual(null, rankToken("", "", "", false, false));
    try testing.expectEqual(null, rankToken("/a", "a", "b", false, false));
    try testing.expectEqual(null, rankToken("c/a", "a", "b", false, false));
    try testing.expectEqual(null, rankToken("/file.ext", "file.ext", "z", false, false));
    try testing.expectEqual(null, rankToken("/file.ext", "file.ext", "fext.", false, false));
    try testing.expectEqual(null, rankToken("/a/b/c", "c", "d", false, false));

    try testing.expect(rankToken("/b", "b", "b", false, false) != null);
    try testing.expect(rankToken("/a/b/c", "c", "c", false, false) != null);
    try testing.expect(rankToken("/file.ext", "file.ext", "ext", false, false) != null);
    try testing.expect(rankToken("path/to/file.ext", "file.ext", "file", false, false) != null);
    try testing.expect(rankToken("path/to/file.ext", "file.ext", "to", false, false) != null);
    try testing.expect(rankToken("path/to/file.ext", "file.ext", "path", false, false) != null);
    try testing.expect(rankToken("path/to/file.ext", "file.ext", "pfile", false, false) != null);
    try testing.expect(rankToken("path/to/file.ext", "file.ext", "ptf", false, false) != null);
    try testing.expect(rankToken("path/to/file.ext", "file.ext", "p/t/f", false, false) != null);

    // strict path matching
    try testing.expectEqual(null, rankToken("a/b", "b", "ab", false, true));
    try testing.expectEqual(null, rankToken("a/b/c", "c", "abc", false, true));
    try testing.expectEqual(null, rankToken("app/monsters/dungeon/foo/bar/baz.rb", "baz.rb", "mod/", false, true));
    try testing.expectEqual(null, rankToken("app/models/foo/bar/baz.rb", "baz.rb", "mod/barbaz", false, true));
    try testing.expectEqual(null, rankToken("/some/path/here", "here", "/somepath", false, true));

    try testing.expect(rankToken("a/b/c", "c", "a/c", false, true) != null);
    try testing.expect(rankToken("a/b/c", "c", "//", false, true) != null);
    try testing.expect(rankToken("src/config/__init__.py", "__init__.py", "con/i", false, true) != null);
    try testing.expect(rankToken("a/b/c/d", "d", "a/b/c", false, true) != null);
    try testing.expect(rankToken("./app/models/foo/bar/baz.rb", "baz.rb", "a/m/f/b/baz", false, true) != null);
    try testing.expect(rankToken("/app/monsters/dungeon/foo/bar/baz.rb", "baz.rb", "a/m/f/b/baz", false, true) != null);
    try testing.expect(rankToken("app/models/foo/bar/baz.rb", "baz.rb", "mod/baz.rb", false, true) != null);
}

/// A simple, append-only array list backed by a fixed buffer
pub fn FixedArrayList(comptime T: type) type {
    return struct {
        buffer: []T,
        len: usize = 0,

        const This = @This();

        pub fn init(buffer: []T) This {
            return .{ .buffer = buffer };
        }

        pub fn append(list: *This, data: T) void {
            if (list.len >= list.buffer.len) return;
            list.buffer[list.len] = data;
            list.len += 1;
        }

        pub fn clear(list: *This) void {
            list.len = 0;
        }

        pub fn slice(list: This) []const T {
            return list.buffer[0..list.len];
        }
    };
}

test "FixedArrayList" {
    var buffer: [4]usize = undefined;
    var list = FixedArrayList(usize).init(&buffer);

    list.append(1);
    list.append(2);
    list.append(3);
    list.append(4);
    list.append(5);
    try testing.expectEqualSlices(usize, &.{ 1, 2, 3, 4 }, list.slice());

    list.clear();
    try testing.expectEqualSlices(usize, &.{}, list.slice());
}

pub fn highlightToken(
    str: []const u8,
    filenameOrNull: ?[]const u8,
    token: []const u8,
    case_sensitive: bool,
    strict_path: bool,
    matches: []usize,
) []const usize {
    if (str.len == 0 or token.len == 0) return &.{};

    var best_rank: ?f64 = null;

    // Working memory for computing matches
    var buf: [1024]usize = undefined;
    var matched = FixedArrayList(usize).init(&buf);
    var best_matched = FixedArrayList(usize).init(matches);

    if (strict_path) {
        var iter = PathIterator.init(token);
        var start: usize = 0;
        while (iter.next()) |segment| {
            var it = IndexIterator.init(str, segment[0], case_sensitive);
            it.index = start;
            while (it.next()) |start_index| {
                matched.append(start_index);

                if (scanToEnd(str, segment[1..], start_index, 0, &matched, case_sensitive, strict_path)) |scan| {
                    // how much of the query token segment matched the path segment?
                    // "mod" would match "module" better than "modules" for example
                    const path_segment_len = segmentLen(str, start_index);
                    const coverage = 1.0 - (@as(f64, @floatFromInt(segment.len)) / @as(f64, @floatFromInt(path_segment_len)));
                    const rank = coverage * scan.rank;

                    if (best_rank == null) {
                        best_rank = rank;
                    } else best_rank = best_rank.? + rank;

                    start = scan.index;
                    for (matched.slice()) |index| best_matched.append(index);
                    break;
                } else matched.clear();
            } else return &.{};

            matched.clear();
        }
        return best_matched.slice();
    }

    // highlight on the filename if requested
    if (filenameOrNull) |filename| {
        // The basename doesn't include trailing slashes so if the string ends in a slash the offset will be off by one
        const offset = str.len - filename.len - @as(usize, if (str[str.len - 1] == sep) 1 else 0);

        var it = IndexIterator.init(filename, token[0], case_sensitive);
        while (it.next()) |start_index| {
            matched.append(start_index + offset);

            if (scanToEnd(filename, token[1..], start_index, offset, &matched, case_sensitive, false)) |scan| {
                if (best_rank == null or scan.rank < best_rank.?) {
                    best_rank = scan.rank;
                    best_matched.clear();
                    for (matched.slice()) |index| best_matched.append(index);
                }
            } else break;
            matched.clear();
        }
        if (best_rank != null) return best_matched.slice();
    }

    matched.clear();

    // highlight the full string if requested or if no match was found on the filename
    var it = IndexIterator.init(str, token[0], case_sensitive);
    while (it.next()) |start_index| {
        matched.append(start_index);

        if (scanToEnd(str, token[1..], start_index, 0, &matched, case_sensitive, false)) |scan| {
            if (best_rank == null or scan.rank < best_rank.?) {
                best_rank = scan.rank;
                best_matched.clear();
                for (matched.slice()) |index| best_matched.append(index);
            }
        } else break;
        matched.clear();
    }

    return best_matched.slice();
}

fn isStartOfWord(byte: u8) bool {
    return switch (byte) {
        sep, '_', '-', '.', ' ' => true,
        else => false,
    };
}

const ScanResult = struct { rank: f64, index: usize };

/// this is the core of the ranking algorithm. special precedence is given to
/// filenames. if a match is found on a filename the candidate is ranked higher
fn scanToEnd(
    str: []const u8,
    token: []const u8,
    start_index: usize,
    offset: usize,
    matched_indices: ?*FixedArrayList(usize),
    case_sensitive: bool,
    strict_path: bool,
) ?ScanResult {
    var rank: f64 = 1;
    var last_index = start_index;
    var last_sequential = false;

    // penalty for not starting on a word boundary
    if (start_index > 0 and !isStartOfWord(str[start_index - 1])) {
        rank += 2.0;
    }

    for (token) |c| {
        const index = if (case_sensitive)
            indexOf(u8, str, last_index + 1, c, true)
        else
            indexOf(u8, str, last_index + 1, c, false);

        if (index) |idx| {
            // did the match span a slash in strict path mode?
            if (strict_path and hasSeparator(str[last_index .. idx + 1])) return null;

            if (matched_indices != null) matched_indices.?.append(idx + offset);

            if (idx == last_index + 1) {
                // sequential matches only count the first character
                if (!last_sequential) {
                    last_sequential = true;
                    rank += 1.0;
                }
            } else {
                // penalty for not starting on a word boundary
                if (!isStartOfWord(str[idx - 1])) {
                    rank += 2.0;
                }

                // normal match
                last_sequential = false;
                rank += @floatFromInt(idx - last_index);
            }

            last_index = idx;
        } else return null;
    }

    return ScanResult{ .rank = rank, .index = last_index + 1 };
}
