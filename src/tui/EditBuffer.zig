//! Manages an editable line of UTF-8 encoded text
//! Assumes all input is valid UTF-8 because it is validated when read in term.zig

const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const EditBuffer = @This();

buffer: ArrayList(u8),
cursor: u16,
dirty: bool,

pub const empty: EditBuffer = .{
    .buffer = .empty,
    .cursor = 0,
    .dirty = false,
};

pub fn deinit(eb: *EditBuffer, allocator: Allocator) void {
    eb.buffer.deinit(allocator);
}

pub fn len(eb: *const EditBuffer) u16 {
    return @intCast(eb.buffer.items.len);
}

pub fn slice(eb: *EditBuffer) []const u8 {
    return eb.buffer.items;
}

/// Insert utf-8 encoded text into the buffer at the cursor position
pub fn insert(eb: *EditBuffer, allocator: Allocator, bytes: []const u8) !void {
    try eb.buffer.insertSlice(allocator, eb.cursor, bytes);
    const bytes_len: u16 = @intCast(bytes.len);
    eb.cursor += bytes_len;
    eb.dirty = true;
}

const Direction = enum { left, right };

/// Delete in the indicated direction
pub fn delete(eb: *EditBuffer, allocator: Allocator, count: usize, direction: Direction) void {
    switch (direction) {
        .left => eb.deleteTo(allocator, eb.cursor -| count),
        .right => eb.deleteTo(allocator, eb.cursor + count),
    }
}

/// Delete from the cursor to the specified position
pub fn deleteTo(eb: *EditBuffer, allocator: Allocator, pos: usize) void {
    const start = @min(eb.cursor, @min(pos, eb.len()));
    const end = @max(eb.cursor, @min(pos, eb.len()));
    if (start == end) return;

    eb.buffer.replaceRange(allocator, start, end - start, "") catch unreachable;

    eb.cursor = start;

    eb.dirty = true;
}

/// Set the cursor to an absolute position
pub fn setCursor(eb: *EditBuffer, pos: u16) void {
    eb.cursor = if (pos > eb.len()) eb.len() else pos;
}

/// Move the cursor relative to it's current position
pub fn moveCursor(eb: *EditBuffer, amount: u16, direction: Direction) void {
    eb.cursor = switch (direction) {
        .left => if (amount >= eb.cursor) 0 else eb.cursor - amount,
        .right => blk: {
            const destination = @addWithOverflow(eb.cursor, amount);

            // if an overflow happened
            if (destination[1] != 0) {
                break :blk eb.len();
            } else {
                if (destination[0] > eb.len()) break :blk eb.len() else break :blk destination[0];
            }
        },
    };
}

test "EditBuffer insert" {
    var eb: EditBuffer = .empty;
    defer eb.deinit(testing.allocator);

    try testing.expectEqual(0, eb.cursor);
    try eb.insert(testing.allocator, "z");
    try testing.expectEqualStrings("z", eb.slice());
    try eb.insert(testing.allocator, "i");
    try testing.expectEqualStrings("zi", eb.slice());
    try eb.insert(testing.allocator, "g");
    try testing.expectEqualStrings("zig", eb.slice());

    try eb.insert(testing.allocator, " ⚡ ");
    try testing.expectEqualStrings("zig ⚡ ", eb.slice());
    try eb.insert(testing.allocator, "¯\\_(ツ)_/¯");
    try testing.expectEqualStrings("zig ⚡ ¯\\_(ツ)_/¯", eb.slice());
    try eb.insert(testing.allocator, " ¾");
    try testing.expectEqualStrings("zig ⚡ ¯\\_(ツ)_/¯ ¾", eb.slice());
}

test "EditBuffer set and move cursor" {
    var eb: EditBuffer = .empty;
    defer eb.deinit(testing.allocator);

    try eb.insert(testing.allocator, "Ä is for Äpfel 🍎, B is for Bear 🧸");

    // test clamping
    eb.setCursor(65535);
    try testing.expectEqual(41, eb.cursor);
    eb.setCursor(0);
    try testing.expectEqual(0, eb.cursor);

    // insert at the beginning
    try eb.insert(testing.allocator, "The Alphabet: ");
    try testing.expectEqualStrings("The Alphabet: Ä is for Äpfel 🍎, B is for Bear 🧸", eb.slice());

    // insert at the end
    eb.setCursor(eb.len());
    try eb.insert(testing.allocator, " ...");
    try testing.expectEqualStrings("The Alphabet: Ä is for Äpfel 🍎, B is for Bear 🧸 ...", eb.slice());

    // relative movement
    eb.setCursor(0);
    eb.moveCursor(4, .right);
    try eb.insert(testing.allocator, "Awesome 💥 ");
    try testing.expectEqualStrings("The Awesome 💥 Alphabet: Ä is for Äpfel 🍎, B is for Bear 🧸 ...", eb.slice());

    // clamping
    eb.moveCursor(65535, .right);
    try testing.expectEqual(72, eb.cursor);
    eb.moveCursor(65535, .left);
    try testing.expectEqual(0, eb.cursor);
}

test "EditBuffer deletion" {
    var eb: EditBuffer = .empty;
    defer eb.deinit(testing.allocator);

    try eb.insert(testing.allocator, "Pokémon 😁 → more ascii here");

    // test bounds
    eb.setCursor(0);
    eb.delete(testing.allocator, 1, .left);
    eb.setCursor(eb.len());
    eb.delete(testing.allocator, 1, .right);
    try testing.expectEqualStrings("Pokémon 😁 → more ascii here", eb.slice());

    eb.setCursor(0);
    eb.delete(testing.allocator, 1, .right);
    eb.setCursor(eb.len());
    eb.delete(testing.allocator, 2, .left);
    try testing.expectEqualStrings("okémon 😁 → more ascii he", eb.slice());

    eb.setCursor(0);
    eb.deleteTo(testing.allocator, 7);
    try testing.expectEqualStrings(" 😁 → more ascii he", eb.slice());

    eb.setCursor(10);
    eb.deleteTo(testing.allocator, 0);
    try testing.expectEqualStrings("more ascii he", eb.slice());

    eb.setCursor(eb.len());
    eb.deleteTo(testing.allocator, 0);
    try testing.expectEqualStrings("", eb.slice());
}
