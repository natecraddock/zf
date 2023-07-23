//! Commandline argument parsing

const std = @import("std");

const eql = std.mem.eql;

const version = "0.9.0-dev";
const version_str = std.fmt.comptimePrint("zf {s} Nathan Craddock", .{version});

const help =
    \\Usage: zf [options]
    \\
    \\-d, --delimiter DELIMITER  Set the delimiter used to split candidates (default \n)
    \\-f, --filter               Skip interactive use and filter using the given query
    \\    --height HEIGHT        The height of the interface in rows (default 10)
    \\-k, --keep-order           Don't sort by rank and preserve order of lines read on stdin
    \\-l, --lines LINES          Alias of --height (deprecated)
    \\-p, --plain                Treat input as plaintext and disable filepath matching features
    \\    --preview COMMAND      Execute COMMAND for the selected line and display the output in a seprate column
    \\    --preview-width WIDTH  Set the preview column width (default 60%)
    \\-v, --version              Show version information and exit
    \\-h, --help                 Display this help and exit
;

const Config = struct {
    help: bool = false,
    version: bool = false,
    skip_ui: bool = false,
    keep_order: bool = false,
    height: usize = 10,
    plain: bool = false,
    query: []u8 = undefined,
    delimiter: []const u8 = "\n",
    preview: ?[]const u8 = null,
    preview_width: usize = 60,

    // HACK: error unions cannot return a value, so return error messages in
    // the config struct instead
    err: bool = false,
    err_str: []u8 = undefined,
};

// TODO: handle args immediately after a short arg, i.e. -qhello or -l5
pub fn parse(allocator: std.mem.Allocator, args: []const []const u8) !Config {
    var config: Config = .{};

    var skip = false;
    for (args[1..], 0..) |arg, i| {
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
        } else if (eql(u8, arg, "-k") or eql(u8, arg, "--keep-order")) {
            config.keep_order = true;
        } else if (eql(u8, arg, "-p") or eql(u8, arg, "--plain")) {
            config.plain = true;
        } else if (eql(u8, arg, "--height") or eql(u8, arg, "-l") or eql(u8, arg, "--lines")) {
            if (index + 1 > args.len - 1) {
                config.err = true;
                config.err_str = try std.fmt.allocPrint(
                    allocator,
                    "zf: option '{s}' requires an argument\n{s}",
                    .{ arg, help },
                );
                return config;
            }

            config.height = try std.fmt.parseUnsigned(usize, args[index + 1], 10);
            if (config.height < 2) return error.Bounds;
            skip = true;
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
        } else if (eql(u8, arg, "-d") or eql(u8, arg, "--delimiter")) {
            if (index + 1 > args.len - 1) {
                config.err = true;
                config.err_str = try std.fmt.allocPrint(
                    allocator,
                    "zf: option '{s}' requires an argument\n{s}",
                    .{ arg, help },
                );
                return config;
            }

            config.delimiter = args[index + 1];
            if (config.delimiter.len == 0) {
                config.err = true;
                config.err_str = try std.fmt.allocPrint(
                    allocator,
                    "zf: delimiter cannot be empty\n{s}",
                    .{help},
                );
                return config;
            }

            skip = true;
        } else if (eql(u8, arg, "--preview")) {
            if (index + 1 > args.len - 1) {
                config.err = true;
                config.err_str = try std.fmt.allocPrint(
                    allocator,
                    "zf: option '{s}' requires an argument\n{s}",
                    .{ arg, help },
                );
                return config;
            }

            config.preview = try allocator.dupe(u8, args[index + 1]);
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
