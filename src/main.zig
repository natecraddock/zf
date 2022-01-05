const std = @import("std");
const heap = std.heap;
const io = std.io;

const ArrayList = std.ArrayList;

const filter = @import("filter.zig");
const ui = @import("ui.zig");

pub fn main() anyerror!void {
    // create an arena allocator to reduce time spent allocating and freeing memory during runtime
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // TODO: read cmd args

    // read all lines or exit on out of memory
    var stdin = io.getStdIn().reader();
    var buf = try readAll(allocator, &stdin);

    const delimiter = '\n';
    var candidates = try filter.collectCandidates(allocator, buf, delimiter);

    var terminal = try ui.Terminal.init();
    var selected = try ui.run(allocator, &terminal, candidates);
    try ui.cleanUp(&terminal);
    terminal.deinit();

    if (selected) |res| {
        defer res.deinit();
        const stdout = std.io.getStdOut().writer();
        try stdout.print("{s}\n", .{res.items});
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
