//! libzf: the zf algorithm exported via the C abi

const std = @import("std");

const filter = @import("filter.zig");
const Candidate = filter.Candidate;
const Range = filter.Range;

export fn rankItem(
    str: [*:0]const u8,
    tokens: [*][*:0]const u8,
    ranges: [*]Range,
    num_tokens: usize,
    filename: bool,
    case_sensitive: bool,
) f64 {
    const string = std.mem.span(str);
    const name = if (filename) std.fs.path.basename(string) else string;
    var candidate: Candidate = .{ .str = string, .name = name };

    var rank: f64 = 0;
    var index: usize = 0;
    while (index < num_tokens) : (index += 1) {
        const token = std.mem.span(tokens[index]);
        if (filter.rankToken(&candidate, &ranges[index], token, !case_sensitive)) |r| {
            rank += r;
        } else return -1.0;
    }

    return rank;
}
