//! libzf: the zf algorithm exported via the C abi

const std = @import("std");

const filter = @import("filter.zig");
const Candidate = filter.Candidate;

export fn rankItem(
    str: [*:0]const u8,
    tokens: [*][*:0]const u8,
    num_tokens: usize,
    filename: bool,
) c_int {
    const string = std.mem.span(str);
    const name = if (filename) std.fs.path.basename(string) else string;
    var candidate: Candidate = .{ .str = string, .name = name };

    var rank: c_int = 0;
    var index: usize = 0;
    while (index < num_tokens) : (index += 1) {
        const token = std.mem.span(tokens[index]);
        if (filter.rankToken(&candidate, token, true)) |r| {
            rank += @intCast(c_int, r);
        } else return -1;
    }

    return rank;
}
