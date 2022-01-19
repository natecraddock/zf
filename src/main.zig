const std = @import("std");
const heap = std.heap;
const io = std.io;
const testing = std.testing;

const ArrayList = std.ArrayList;

const filter = @import("filter.zig");
const ui = @import("ui.zig");

const version = "0.0.1";
const version_str = std.fmt.comptimePrint("zf {s} Nathan Craddock", .{version});

const help =
    \\Usage: zf [options]
    \\
    \\-f, --filter  Skip interactive use and filter using the given query
    \\-v, --version Show version information and exit
    \\-h, --help    Display this help and exit
;

const Config = struct {
    help: bool = false,
    version: bool = false,
    skip_ui: bool = false,
    query: []u8 = undefined,

    // HACK: error unions cannot return a value, so return error messages in
    // the config struct instead
    err: bool = false,
    err_str: []u8 = undefined,
};

fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !Config {
    var config: Config = .{};

    const eql = std.mem.eql;
    var skip = false;
    for (args[1..]) |arg, i| {
        if (skip) {
            skip = false;
            continue;
        }

        const index = i + 1;
        if (eql(u8, arg, "-h") or eql(u8, arg, "--help")) {
            config.help = true;
            return config;
        } else if (eql(u8, arg, "-v") or eql(u8, arg, "--version")) {
            config.version = true;
            return config;
        } else if (eql(u8, arg, "-f") or eql(u8, arg, "--filter")) {
            config.skip_ui = true;

            // read query
            if (index + 1 > args.len - 1) {
                config.err = true;
                config.err_str = try std.fmt.allocPrint(
                    allocator,
                    "zf: option '{s}' requires an argument\n{s}",
                    .{ arg, help },
                );
                return config;
            }

            config.query = try allocator.alloc(u8, args[index + 1].len);
            std.mem.copy(u8, config.query, args[index + 1]);
            skip = true;
        } else {
            config.err = true;
            config.err_str = try std.fmt.allocPrint(
                allocator,
                "zf: unrecognized option '{s}'\n{s}",
                .{ arg, help },
            );
            return config;
        }
    }

    return config;
}

test "parse args" {
    {
        const args = [_][]const u8{"zf"};
        const config = try parseArgs(testing.allocator, &args);
        const expected: Config = .{};
        try testing.expectEqual(expected, config);
    }
    {
        const args = [_][]const u8{ "zf", "--help" };
        const config = try parseArgs(testing.allocator, &args);
        const expected: Config = .{ .help = true };
        try testing.expectEqual(expected, config);
    }
    {
        const args = [_][]const u8{ "zf", "--version" };
        const config = try parseArgs(testing.allocator, &args);
        const expected: Config = .{ .version = true };
        try testing.expectEqual(expected, config);
    }
    {
        const args = [_][]const u8{ "zf", "-v", "-h" };
        const config = try parseArgs(testing.allocator, &args);
        const expected: Config = .{ .help = false, .version = true };
        try testing.expectEqual(expected, config);
    }
    {
        const args = [_][]const u8{ "zf", "-f", "query" };
        const config = try parseArgs(testing.allocator, &args);
        defer testing.allocator.free(config.query);

        try testing.expect(config.skip_ui);
        try testing.expectEqualStrings("query", config.query);
    }

    // failure cases
    {
        const args = [_][]const u8{ "zf", "--filter" };
        const config = try parseArgs(testing.allocator, &args);
        defer testing.allocator.free(config.err_str);
        try testing.expect(config.err);
    }
    {
        const args = [_][]const u8{ "zf", "asdf" };
        const config = try parseArgs(testing.allocator, &args);
        defer testing.allocator.free(config.err_str);
        try testing.expect(config.err);
    }
    {
        const args = [_][]const u8{ "zf", "bad arg here", "--help" };
        const config = try parseArgs(testing.allocator, &args);
        defer testing.allocator.free(config.err_str);
        try testing.expect(config.err);
    }
}

pub fn main() anyerror!void {
    // create an arena allocator to reduce time spent allocating
    // and freeing memory during runtime.
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    const config = try parseArgs(allocator, args);

    if (config.err) {
        try stderr.print("{s}\n", .{config.err_str});
        std.process.exit(2);
    } else if (config.help) {
        try stdout.print("{s}\n", .{help});
        std.process.exit(0);
    } else if (config.version) {
        try stdout.print("{s}\n", .{version_str});
        std.process.exit(0);
    }

    // read all lines or exit on out of memory
    var stdin = io.getStdIn().reader();
    const buf = try readAll(allocator, &stdin);

    const delimiter = '\n';
    var candidates = try filter.collectCandidates(allocator, buf, delimiter);
    if (candidates.len == 0) std.process.exit(1);

    if (config.skip_ui) {
        const filtered = try filter.rankCandidates(allocator, candidates, config.query);
        if (filtered.len == 0) std.process.exit(1);
        for (filtered) |candidate| {
            try stdout.print("{s}\n", .{candidate.str});
        }
    } else {
        var terminal = try ui.Terminal.init();
        var selected = try ui.run(allocator, &terminal, candidates);
        try ui.cleanUp(&terminal);
        terminal.deinit();

        if (selected) |result| {
            defer result.deinit();
            try stdout.print("{s}\n", .{result.items});
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
    _ = @import("filter.zig");
}
