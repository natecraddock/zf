//! Commandline argument parsing

const fmt = std.fmt;
const mem = std.mem;
const process = std.process;
const std = @import("std");

const Allocator = mem.Allocator;
const File = std.fs.File;

const version = "0.9.0-dev";
const version_str = std.fmt.comptimePrint("zf {s} Nathan Craddock", .{version});

const help =
    \\Usage: zf [options]
    \\
    \\-d, --delimiter DELIMITER  Set the delimiter used to split candidates (default \n)
    \\-0                         Shorthand for -d'\0' to split on null bytes
    \\-f, --filter QUERY         Skip interactive use and filter using the given query
    \\    --height HEIGHT        The height of the interface in rows (default 10)
    \\-k, --keep-order           Don't sort by rank and preserve order of lines read on stdin
    \\-l, --lines LINES          Alias of --height (deprecated)
    \\-p, --plain                Treat input as plaintext and disable filepath matching features
    \\    --preview COMMAND      Execute COMMAND for the selected line and display the output in a seprate column
    \\    --preview-width WIDTH  Set the preview column width (default 60%)
    \\-v, --version              Show version information and exit
    \\-h, --help                 Display this help and exit
;

const OptionIter = struct {
    args: []const []const u8,
    index: usize = 0,
    short_index: ?usize = null,

    pub fn next(self: *OptionIter) ?[]const u8 {
        if (self.index >= self.args.len) return null;

        // Iterating through multiple short options in a row e.g. -kpf
        if (self.short_index) |_| {
            if (self.nextShort()) |short| {
                return short;
            } else self.index += 1;
        }

        if (self.index >= self.args.len) return null;

        const arg = self.args[self.index];
        if (mem.startsWith(u8, arg, "--") and arg.len > 2) {
            self.index += 1;
            return arg[2..];
        } else if (mem.startsWith(u8, arg, "-") and arg.len > 1) {
            self.short_index = 1;
            if (self.nextShort()) |short| {
                return short;
            }
        }

        return null;
    }

    fn nextShort(self: *OptionIter) ?[]const u8 {
        const arg = self.args[self.index];
        if (self.short_index.? >= arg.len) {
            self.short_index = null;
            return null;
        }

        const short = arg[self.short_index.?..][0..1];
        self.short_index.? += 1;
        return short;
    }

    pub fn getArg(self: *OptionIter) ?[]const u8 {
        // when parsing multiple short args the argument can be joined without a space
        if (self.short_index) |index| {
            const arg = self.args[self.index];
            self.short_index = null;
            if (index < arg.len) {
                self.index += 1;
                return arg[index..];
            }
            self.index += 1;
        }

        if (self.index >= self.args.len) return null;

        const arg = self.args[self.index];
        self.index += 1;
        return arg;
    }
};

pub const Config = struct {
    keep_order: bool = false,
    height: usize = 10,
    filter: ?[]const u8 = null,
    plain: bool = false,
    delimiter: []const u8 = "\n",
    preview: ?[]const u8 = null,
    preview_width: f64 = 0.6,
};

pub fn parse(allocator: Allocator, args: []const []const u8, stderr: File.Writer) Config {
    var config: Config = .{};

    if (args.len == 1) return config;

    var iter: OptionIter = .{ .args = args[1..] };
    while (iter.next()) |opt| {
        // help
        if (mem.eql(u8, opt, "h") or mem.eql(u8, opt, "help")) {
            stderr.print("{s}\n", .{help}) catch unreachable;
            process.exit(0);
        }

        // version
        else if (mem.eql(u8, opt, "v") or mem.eql(u8, opt, "version")) {
            stderr.print("{s}\n", .{version_str}) catch unreachable;
            process.exit(0);
        }

        // delimiter
        else if (mem.eql(u8, opt, "d") or mem.eql(u8, opt, "delimiter")) {
            const delimiter = iter.getArg() orelse missingArg(stderr, iter, opt);
            if (delimiter.len == 0) argError(stderr, "delimiter cannot be empty");
            config.delimiter = allocator.dupe(u8, delimiter) catch unreachable;
        }
        else if (mem.eql(u8, opt, "0")) {
            config.delimiter = allocator.dupe(u8, &.{ 0 }) catch unreachable;
        }

        // filter
        else if (mem.eql(u8, opt, "f") or mem.eql(u8, opt, "filter")) {
            const filter = iter.getArg() orelse missingArg(stderr, iter, opt);
            config.filter = allocator.dupe(u8, filter) catch unreachable;
        }

        // height
        else if (mem.eql(u8, opt, "height") or mem.eql(u8, opt, "l") or mem.eql(u8, opt, "lines")) {
            const height_str = iter.getArg() orelse missingArg(stderr, iter, opt);
            const height = fmt.parseUnsigned(usize, height_str, 10) catch argError(stderr, "height must be an integer");
            if (height < 2) argError(stderr, "height must be an integer greater than 1");
            config.height = height;
        }

        // keep-order
        else if (mem.eql(u8, opt, "k") or mem.eql(u8, opt, "keep-order")) {
            config.keep_order = true;
        }

        // plain
        else if (mem.eql(u8, opt, "p") or mem.eql(u8, opt, "plain")) {
            config.plain = true;
        }

        // preview
        else if (mem.eql(u8, opt, "preview")) {
            const command = iter.getArg() orelse missingArg(stderr, iter, opt);
            config.preview = allocator.dupe(u8, command) catch unreachable;
        }

        // preview-width
        else if (mem.eql(u8, opt, "preview-width")) {
            const width_str = blk: {
                const arg = iter.getArg() orelse missingArg(stderr, iter, opt);
                if (mem.endsWith(u8, arg, "%")) break :blk arg[0 .. arg.len - 1];
                break :blk arg;
            };
            const preview_width = fmt.parseUnsigned(usize, width_str, 10) catch argError(stderr, "preview-width must be an integer");
            if (preview_width < 20 or preview_width > 80) argError(stderr, "preview-width must be between 20% and 80%");

            config.preview_width = @as(f64, @floatFromInt(preview_width)) / 100.0;
        }

        // invalid option
        else {
            stderr.print("zf: unrecognized option '{s}{s}'\n{s}\n", .{ if (iter.short_index != null) "-" else "--", opt, help }) catch unreachable;
            process.exit(2);
        }
    }

    return config;
}

fn missingArg(stderr: File.Writer, iter: OptionIter, opt: []const u8) noreturn {
    stderr.print(
        "zf: option '{s}{s}' requires an argument\n{s}\n",
        .{ if (iter.short_index != null) "-" else "--", opt, help },
    ) catch unreachable;
    process.exit(2);
}

fn argError(stderr: File.Writer, err: []const u8) noreturn {
    stderr.print("zf: {s}\n{s}\n", .{ err, help }) catch unreachable;
    process.exit(2);
}

const testing = std.testing;
const expectEqualStrings = testing.expectEqualStrings;

test "OptionIter" {
    // short option
    {
        var iter: OptionIter = .{ .args = &.{"-h"} };
        try expectEqualStrings("h", iter.next().?);
    }

    // short option with argument
    {
        var iter: OptionIter = .{ .args = &.{"-fa"} };
        try expectEqualStrings("f", iter.next().?);
        try expectEqualStrings("a", iter.getArg().?);
    }

    // chained short options
    {
        var iter: OptionIter = .{ .args = &.{"-abcd"} };
        try expectEqualStrings("a", iter.next().?);
        try expectEqualStrings("b", iter.next().?);
        try expectEqualStrings("c", iter.next().?);
        try expectEqualStrings("d", iter.next().?);
    }

    // chained short options with connected argument
    {
        var iter: OptionIter = .{ .args = &.{"-afargument"} };
        try expectEqualStrings("a", iter.next().?);
        try expectEqualStrings("f", iter.next().?);
        try expectEqualStrings("argument", iter.getArg().?);
    }

    // chained short options with argument
    {
        var iter: OptionIter = .{ .args = &.{ "-af", "argument" } };
        try expectEqualStrings("a", iter.next().?);
        try expectEqualStrings("f", iter.next().?);
        try expectEqualStrings("argument", iter.getArg().?);
    }

    // long option
    {
        var iter: OptionIter = .{ .args = &.{"--help"} };
        try expectEqualStrings("help", iter.next().?);
    }

    // long option with argument
    {
        var iter: OptionIter = .{ .args = &.{ "--filter", "argument" } };
        try expectEqualStrings("filter", iter.next().?);
        try expectEqualStrings("argument", iter.getArg().?);
    }

    // mixed
    {
        var iter: OptionIter = .{ .args = &.{ "-a", "arg", "--long", "-sbarg", "--long", "-abcopt", "-a", "opt", "--long", "--flag", "opt" } };
        try expectEqualStrings("a", iter.next().?);
        try expectEqualStrings("arg", iter.getArg().?);
        try expectEqualStrings("long", iter.next().?);
        try expectEqualStrings("s", iter.next().?);
        try expectEqualStrings("b", iter.next().?);
        try expectEqualStrings("arg", iter.getArg().?);
        try expectEqualStrings("long", iter.next().?);
        try expectEqualStrings("a", iter.next().?);
        try expectEqualStrings("b", iter.next().?);
        try expectEqualStrings("c", iter.next().?);
        try expectEqualStrings("opt", iter.getArg().?);
        try expectEqualStrings("a", iter.next().?);
        try expectEqualStrings("opt", iter.getArg().?);
        try expectEqualStrings("long", iter.next().?);
        try expectEqualStrings("flag", iter.next().?);
        try expectEqualStrings("opt", iter.getArg().?);
        try testing.expect(iter.next() == null);
    }
}
