const std = @import("std");
const ArrayList = std.ArrayList;

pub fn filter(allocator: *std.mem.Allocator, options: [][]const u8, query: []const u8) !ArrayList([]const u8) {
    var filtered = ArrayList([]const u8).init(allocator);

    for (options) |option, index| {
        if (std.mem.count(u8, option, query) > 0) {
            try filtered.append(option);
        }
    }

    return filtered;
}
