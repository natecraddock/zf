const std = @import("std");
const testing = std.testing;
const zf = @import("zf");

const ArrayList = std.ArrayList;

/// Candidates are the strings read from stdin
pub const Candidate = struct {
    str: []const u8,
    rank: f64 = 0,
};

/// read the candidates from the buffer
pub fn collect(allocator: std.mem.Allocator, buf: []const u8, delimiter: u8) ![][]const u8 {
    var candidates = ArrayList([]const u8).init(allocator);

    // find delimiters
    var start: usize = 0;
    for (buf, 0..) |char, index| {
        if (char == delimiter) {
            // add to arraylist only if slice is not all delimiters
            if (index - start != 0) {
                try candidates.append(buf[start..index]);
            }
            start = index + 1;
        }
    }

    // catch the end if stdio didn't end in a delimiter
    if (start < buf.len and buf[start] != delimiter) {
        try candidates.append(buf[start..]);
    }

    return candidates.toOwnedSlice();
}

test "collect whitespace" {
    const candidates = try collect(testing.allocator, "first second third fourth", ' ');
    defer testing.allocator.free(candidates);

    try testing.expectEqual(4, candidates.len);
    try testing.expectEqualStrings("first", candidates[0]);
    try testing.expectEqualStrings("second", candidates[1]);
    try testing.expectEqualStrings("third", candidates[2]);
    try testing.expectEqualStrings("fourth", candidates[3]);
}

test "collect newline" {
    const candidates = try collect(testing.allocator, "first\nsecond\nthird\nfourth", '\n');
    defer testing.allocator.free(candidates);

    try testing.expectEqual(4, candidates.len);
    try testing.expectEqualStrings("first", candidates[0]);
    try testing.expectEqualStrings("second", candidates[1]);
    try testing.expectEqualStrings("third", candidates[2]);
    try testing.expectEqualStrings("fourth", candidates[3]);
}

test "collect excess whitespace" {
    const candidates = try collect(testing.allocator, "   first second   third fourth   ", ' ');
    defer testing.allocator.free(candidates);

    try testing.expectEqual(4, candidates.len);
    try testing.expectEqualStrings("first", candidates[0]);
    try testing.expectEqualStrings("second", candidates[1]);
    try testing.expectEqualStrings("third", candidates[2]);
    try testing.expectEqualStrings("fourth", candidates[3]);
}

/// rank each candidate against the query
///
/// returns a sorted slice of Candidates that match the query ready for display
/// in a tui or output to stdout
pub fn rank(
    ranked: []Candidate,
    candidates: []const []const u8,
    tokens: []const []const u8,
    keep_order: bool,
    plain: bool,
    case_sensitive: bool,
) []Candidate {
    if (tokens.len == 0) {
        for (candidates, 0..) |candidate, index| {
            ranked[index] = .{ .str = candidate };
        }
        return ranked;
    }

    var index: usize = 0;
    for (candidates) |candidate| {
        if (zf.rank(candidate, tokens, case_sensitive, plain)) |r| {
            ranked[index] = .{ .str = candidate, .rank = r };
            index += 1;
        }
    }

    if (!keep_order) {
        std.sort.block(Candidate, ranked[0..index], {}, sort);
    }

    return ranked[0..index];
}

fn sort(_: void, a: Candidate, b: Candidate) bool {
    // first by rank
    if (a.rank < b.rank) return true;
    if (a.rank > b.rank) return false;

    // then by length
    if (a.str.len < b.str.len) return true;
    if (a.str.len > b.str.len) return false;

    // then alphabetically
    for (a.str, 0..) |c, i| {
        if (c < b.str[i]) return true;
        if (c > b.str[i]) return false;
    }
    return false;
}

// These tests are arguably the most important in zf. They ensure the ordering of filtered
// items is maintained when updating the filter algorithms. The test cases are based on
// experience with other fuzzy finders that led to the creation of zf. When I find new
// ways to improve the filtering algorithm these tests should all pass, and new tests
// should be added to ensure the filtering doesn't break. The tests don't check the actual
// rank value, only the order of the first n results.

fn testRankCandidates(
    tokens: []const []const u8,
    candidates: []const []const u8,
    expected: []const []const u8,
) !void {
    const ranked_buf = try testing.allocator.alloc(Candidate, candidates.len);
    defer testing.allocator.free(ranked_buf);
    const ranked = rank(ranked_buf, candidates, tokens, false, false, false);

    for (expected, 0..) |expected_str, i| {
        if (!std.mem.eql(u8, expected_str, ranked[i].str)) {
            std.debug.print("\n======= order incorrect: ========\n", .{});
            for (ranked[0..@min(ranked.len, expected.len)]) |candidate| std.debug.print("{s}\n", .{candidate.str});
            std.debug.print("\n========== expected: ===========\n", .{});
            for (expected) |str| std.debug.print("{s}\n", .{str});
            std.debug.print("\n================================", .{});
            std.debug.print("\nwith query:", .{});
            for (tokens) |token| std.debug.print(" {s}", .{token});
            std.debug.print("\n\n", .{});

            return error.TestOrderIncorrect;
        }
    }
}

test "zf ranking consistency" {
    // Filepaths from Blender. Both fzf and fzy rank DNA_genfile.h first
    try testRankCandidates(
        &.{"make"},
        &.{
            "source/blender/makesrna/intern/rna_cachefile.c",
            "source/blender/makesdna/intern/dna_genfile.c",
            "source/blender/makesdna/DNA_curveprofile_types.h",
            "source/blender/makesdna/DNA_genfile.h",
            "GNUmakefile",
        },
        &.{"GNUmakefile"},
    );

    // From issue #3, prioritize filename coverage
    try testRankCandidates(&.{"a"}, &.{ "/path/a.c", "abcd" }, &.{"/path/a.c"});
    try testRankCandidates(
        &.{"app.py"},
        &.{
            "./myownmod/custom/app.py",
            "./tests/test_app.py",
        },
        &.{"./tests/test_app.py"},
    );

    // From issue #24, some really great test cases (thanks @ratfactor!)
    const candidates = [_][]const u8{
        "oat/meal/sug/ar",
        "oat/meal/sug/ar/sugar",
        "oat/meal/sug/ar/sugar.txt",
        "oat/meal/sug/ar/sugar.js",
        "oatmeal/sugar/sugar.txt",
        "oatmeal/sugar/snakes.txt",
        "oatmeal/sugar/skeletons.txt",
        "oatmeal/brown_sugar.txt",
        "oatmeal/brown_sugar/brown.js",
        "oatmeal/brown_sugar/sugar.js",
        "oatmeal/brown_sugar/brown_sugar.js",
        "oatmeal/brown_sugar/sugar_brown.js",
        "oatmeal/granulated_sugar.txt",
        "oatmeal/raisins/sugar.js",
    };
    try testRankCandidates(
        &.{ "oat/sugar", "sugar/sugar", "meal/sugar" },
        &candidates,
        &.{ "oatmeal/sugar/sugar.txt", "oatmeal/brown_sugar/sugar.js", "oatmeal/brown_sugar/brown_sugar.js" },
    );
    try testRankCandidates(&.{ "oat/sugar", "brown" }, &candidates, &.{"oatmeal/brown_sugar/brown.js"});
    try testRankCandidates(&.{"oat/sn"}, &candidates, &.{"oatmeal/sugar/snakes.txt"});
    try testRankCandidates(&.{"oat/skel"}, &candidates, &.{"oatmeal/sugar/skeletons.txt"});

    // Strict path matching better ranking
    try testRankCandidates(
        &.{"mod/baz.rb"},
        &.{
            "./app/models/foo-bar-baz.rb",
            "./app/models/foo/bar-baz.rb",
            "./app/models/foo/bar/baz.rb",
        },
        &.{"./app/models/foo/bar/baz.rb"},
    );
}
