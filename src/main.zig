const filter = @import("filter.zig");
const heap = std.heap;
const io = std.io;
const opts = @import("opts.zig");
const std = @import("std");
const term = @import("term.zig");
const testing = std.testing;
const ui = @import("ui.zig");
const ziglyph = @import("ziglyph");

const ArrayList = std.ArrayList;
const Normalizer = ziglyph.Normalizer;
const SGRAttribute = term.SGRAttribute;
const Terminal = term.Terminal;

const eql = std.mem.eql;

// Override the root os so we aren't forced to use libc on Linux (which is missing some constants)
pub const os = struct {
    pub const system = switch (@import("builtin").os.tag) {
        .linux => std.os.linux,
        else => std.c,
    };
};

pub fn main() anyerror!void {
    // create an arena allocator to reduce time spent allocating
    // and freeing memory during runtime.
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    const config = opts.parse(allocator, args, stderr);

    var normalizer = try Normalizer.init(allocator);
    defer normalizer.deinit();

    // read all lines or exit on out of memory
    const buf = blk: {
        var stdin = io.getStdIn().reader();
        const buf = try readAll(allocator, &stdin);
        break :blk std.mem.trim(u8, (try normalizer.nfd(allocator, buf)).slice, "\n");
    };

    // escape specific delimiters
    const delimiter = blk: {
        if (eql(u8, config.delimiter, "\\n")) {
            break :blk '\n';
        } else if (eql(u8, config.delimiter, "\\0")) {
            break :blk 0;
        } else {
            break :blk config.delimiter[0];
        }
    };

    var candidates = try filter.collectCandidates(allocator, buf, delimiter);
    if (candidates.len == 0) std.process.exit(1);

    if (config.filter) |query| {
        // Use the heap here rather than an array on the stack. Testing showed that this is actually
        // faster, likely due to locality with other heap-alloced data used in the algorithm.
        var tokens_buf = try allocator.alloc([]const u8, 16);
        const tokens = ui.splitQuery(tokens_buf, query);
        const case_sensitive = ui.hasUpper(query);
        var filtered_buf = try allocator.alloc(filter.Candidate, candidates.len);
        const filtered = filter.rankCandidates(filtered_buf, candidates, tokens, config.keep_order, config.plain, case_sensitive);
        if (filtered.len == 0) std.process.exit(1);
        for (filtered) |candidate| {
            try stdout.print("{s}\n", .{candidate.str});
        }
    } else {
        const prompt_str = std.process.getEnvVarOwned(allocator, "ZF_PROMPT") catch "> ";
        const vi_mode = if (std.process.getEnvVarOwned(allocator, "ZF_VI_MODE")) |value| blk: {
            break :blk value.len > 0;
        } else |_| false;
        const no_color = if (std.process.getEnvVarOwned(allocator, "NO_COLOR")) |value| blk: {
            break :blk value.len > 0;
        } else |_| false;
        const highlight_color: SGRAttribute = if (std.process.getEnvVarOwned(allocator, "ZF_HIGHLIGHT")) |value| blk: {
            inline for (std.meta.fields(SGRAttribute)) |field| {
                if (eql(u8, value, field.name)) {
                    break :blk @enumFromInt(field.value);
                }
            }
            break :blk .cyan;
        } else |_| .cyan;

        var terminal = try Terminal.init(highlight_color, no_color);
        var selected = ui.run(
            allocator,
            &terminal,
            normalizer,
            candidates,
            config.keep_order,
            config.plain,
            config.height,
            config.preview,
            config.preview_width,
            prompt_str,
            vi_mode,
        ) catch |err| switch (err) {
            error.UnknownANSIEscape => {
                try terminal.deinit(0);
                try stderr.print("zf: unknown ANSI escape sequence in ZF_PROMPT\n", .{});
                std.process.exit(2);
            },
            else => {
                try terminal.deinit(0);
                return err;
            },
        };

        try terminal.deinit(config.height);

        if (selected) |selected_lines| {
            for (selected_lines) |str| {
                try stdout.print("{s}\n", .{str});
            }
        } else std.process.exit(1);
    }
}

/// read from a file into an ArrayList. similar to readAllAlloc from the
/// standard library, but will read until out of memory rather than limiting to
/// a maximum size.
pub fn readAll(allocator: std.mem.Allocator, reader: *std.fs.File.Reader) ![]u8 {
    var buf = ArrayList(u8).init(allocator);

    // ensure the array starts at a decent size
    try buf.ensureTotalCapacity(4096);

    var index: usize = 0;
    while (true) {
        buf.expandToCapacity();
        const slice = buf.items[index..];
        const read = try reader.readAll(slice);
        index += read;

        if (read != slice.len) {
            buf.shrinkAndFree(index);
            return buf.toOwnedSlice();
        }

        try buf.ensureTotalCapacity(index + 1);
    }
}

test {
    _ = @import("array_toggle_set.zig");
    _ = @import("clib.zig");
    _ = @import("EditBuffer.zig");
    _ = @import("filter.zig");
    _ = @import("lib.zig");
    _ = @import("opts.zig");
    _ = @import("ui.zig");
}
