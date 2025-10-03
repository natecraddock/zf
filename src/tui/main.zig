const candidate = @import("candidate.zig");
const heap = std.heap;
const io = std.io;
const opts = @import("opts.zig");
const std = @import("std");
const testing = std.testing;
const ui = @import("ui.zig");
const vaxis = @import("vaxis");

const ArrayList = std.ArrayList;
const Candidate = candidate.Candidate;
const Color = ui.Color;

pub const std_options: std.Options = .{
    .log_level = .err,
};

const eql = std.mem.eql;

pub const panic = vaxis.panic_handler;

pub fn main() anyerror!void {
    // create an arena allocator to reduce time spent allocating
    // and freeing memory during runtime.
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);

    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;

    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    var config = opts.parse(allocator, args, stderr);

    // read all lines or exit on out of memory
    const buf = blk: {
        var stdin_buf: [1024]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
        const stdin = &stdin_reader.interface;

        const buf = try stdin.allocRemaining(allocator, .unlimited);

        break :blk std.mem.trim(u8, buf, "\n");
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

    const candidates = try candidate.collect(allocator, buf, delimiter);
    if (candidates.len == 0) std.process.exit(1);

    defer stdout.flush() catch unreachable;
    if (config.filter) |query| {
        // Use the heap here rather than an array on the stack. Testing showed that this is actually
        // faster, likely due to locality with other heap-alloced data used in the algorithm.
        const tokens_buf = try allocator.alloc([]const u8, 16);
        const tokens = ui.splitQuery(tokens_buf, query);
        const case_sensitive = ui.hasUpper(query);
        const filtered_buf = try allocator.alloc(Candidate, candidates.len);
        const filtered = candidate.rank(filtered_buf, candidates, tokens, config.keep_order, config.plain, case_sensitive);
        if (filtered.len == 0) std.process.exit(1);
        for (filtered) |c| {
            try stdout.print("{s}\n", .{c.str});
        }
    } else {
        config.prompt = std.process.getEnvVarOwned(allocator, "ZF_PROMPT") catch "> ";
        config.vi_mode = if (std.process.getEnvVarOwned(allocator, "ZF_VI_MODE")) |value| blk: {
            break :blk value.len > 0;
        } else |_| false;

        {
            const no_color = if (std.process.getEnvVarOwned(allocator, "NO_COLOR")) |value| blk: {
                break :blk value.len > 0;
            } else |_| false;

            const highlight_color: Color = if (std.process.getEnvVarOwned(allocator, "ZF_HIGHLIGHT")) |value| blk: {
                inline for (std.meta.fields(Color)) |field| {
                    if (eql(u8, value, field.name)) {
                        break :blk @enumFromInt(field.value);
                    }
                }
                break :blk .cyan;
            } else |_| .cyan;

            config.highlight = if (no_color) null else highlight_color;
        }

        var tui_buf: [1024]u8 = undefined;
        var state = try ui.State.init(allocator, &tui_buf, config);
        const selected = try state.run(candidates);

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
    _ = @import("EditBuffer.zig");
    _ = @import("candidate.zig");
    _ = @import("opts.zig");
    _ = @import("ui.zig");
    _ = @import("Previewer.zig");
}
