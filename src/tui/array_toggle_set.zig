const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// Manages a set based on an array list (with O(n) efficiency)
/// Not efficient for large sizes of n of course, but for small use cases works well enough
/// The most important part is that it maintains the order of the items in the set
pub fn ArrayToggleSet(comptime T: type) type {
    return struct {
        set: ArrayList(T),

        const This = @This();

        pub const empty: This = .{ .set = .empty };

        pub fn deinit(as: *This, allocator: Allocator) void {
            as.set.deinit(allocator);
        }

        pub fn clear(as: *This) void {
            as.set.clearRetainingCapacity();
        }

        pub fn toggle(as: *This, allocator: Allocator, item: T) !void {
            for (as.set.items, 0..) |i, index| {
                if (item == i) {
                    _ = as.set.orderedRemove(index);
                    return;
                }
                if (i > item) {
                    try as.set.insert(allocator, index, item);
                    return;
                }
            }
            try as.set.append(allocator, item);
        }

        pub fn contains(as: This, item: T) bool {
            for (as.set.items) |i| {
                if (item == i) return true;
            }
            return false;
        }

        pub fn slice(as: This) []const T {
            return as.set.items;
        }
    };
}

test "basic ArrayToggleSet" {
    var items: ArrayToggleSet(u8) = .empty;
    defer items.deinit(testing.allocator);

    try items.toggle(testing.allocator, 1);
    try items.toggle(testing.allocator, 2);
    try items.toggle(testing.allocator, 4);
    try items.toggle(testing.allocator, 10);

    try testing.expect(items.contains(10));
    try testing.expect(!items.contains(100));

    try testing.expectEqualSlices(u8, &.{ 1, 2, 4, 10 }, items.slice());
}

test "unordered insertion ArrayToggleSet" {
    var items: ArrayToggleSet(u8) = .empty;
    defer items.deinit(testing.allocator);

    try items.toggle(testing.allocator, 10);
    try items.toggle(testing.allocator, 1);
    try items.toggle(testing.allocator, 4);
    try items.toggle(testing.allocator, 2);

    try testing.expectEqualSlices(u8, &.{ 1, 2, 4, 10 }, items.slice());
}

test "removal ArrayToggleSet" {
    var items: ArrayToggleSet(u8) = .empty;
    defer items.deinit(testing.allocator);

    try items.toggle(testing.allocator, 10);
    try items.toggle(testing.allocator, 1);
    try items.toggle(testing.allocator, 4);
    try items.toggle(testing.allocator, 2);

    try items.toggle(testing.allocator, 1);
    try items.toggle(testing.allocator, 10);
    try testing.expectEqualSlices(u8, &.{ 2, 4 }, items.slice());

    try items.toggle(testing.allocator, 1);
    try items.toggle(testing.allocator, 100);
    try items.toggle(testing.allocator, 3);
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 100 }, items.slice());

    items.clear();
    try testing.expectEqualSlices(u8, &.{}, items.slice());
}
