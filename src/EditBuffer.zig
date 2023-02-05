//! Manages an editable line of UTF-8 encoded text
//! Assumes all input is valid UTF-8 because it is validated when read in term.zig

const std = @import("std");
const testing = std.testing;
const ziglyph = @import("ziglyph");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const GraphemeIterator = ziglyph.GraphemeIterator;

const EditBuffer = @This();

buffer: ArrayList(u8),
len: usize,
cursor: usize,
dirty: bool,

pub fn init(allocator: Allocator) EditBuffer {
    return .{
        .buffer = ArrayList(u8).init(allocator),
        .len = 0,
        .cursor = 0,
        .dirty = false,
    };
}

pub fn deinit(eb: *EditBuffer) void {
    eb.buffer.deinit();
}

pub fn slice(eb: *EditBuffer) []const u8 {
    return eb.buffer.items;
}

pub fn sliceRange(eb: *EditBuffer, start: usize, end: usize) []const u8 {
    const start_index = eb.cursorToBufferIndex(start);
    const end_index = eb.cursorToBufferIndex(end);
    return eb.buffer.items[start_index..end_index];
}

/// Insert utf-8 encoded text into the buffer at the cursor position
pub fn insert(eb: *EditBuffer, bytes: []const u8) !void {
    const index = eb.cursorToBufferIndex(eb.cursor);
    try eb.buffer.insertSlice(index, bytes);

    const len = utf8Len(bytes);
    eb.cursor += len;
    eb.len += len;

    eb.dirty = true;
}

const Direction = enum { left, right };

/// Delete count graphemes in the indicated direction
pub fn delete(eb: *EditBuffer, count: usize, direction: Direction) void {
    switch (direction) {
        .left => eb.deleteTo(eb.cursor -| count),
        .right => eb.deleteTo(eb.cursor + count),
    }
}

/// Delete graphemes from the cursor to the specified position
pub fn deleteTo(eb: *EditBuffer, pos: usize) void {
    const start = @min(eb.cursor, @min(pos, eb.len));
    const end = @max(eb.cursor, @min(pos, eb.len));
    if (start == end) return;

    const start_byte = eb.cursorToBufferIndex(start);
    const end_byte = eb.cursorToBufferIndex(end);
    eb.buffer.replaceRange(start_byte, end_byte - start_byte, "") catch unreachable;

    eb.cursor = start;
    eb.len -= end - start;

    eb.dirty = true;
}

/// Set the cursor to an absolute position
pub fn setCursor(eb: *EditBuffer, pos: usize) void {
    eb.cursor = if (pos > eb.len) eb.len else pos;
}

/// Move the cursor relative to it's current position
pub fn moveCursor(eb: *EditBuffer, amount: usize, direction: Direction) void {
    eb.cursor = switch (direction) {
        .left => if (amount >= eb.cursor) 0 else eb.cursor - amount,
        .right => if (eb.cursor + amount > eb.len) eb.len else eb.cursor + amount,
    };
}

// Return the buffer index of the cursor
pub fn cursorIndex(eb: *EditBuffer) usize {
    return eb.cursorToBufferIndex(eb.cursor);
}

/// Converts a cursor position to a buffer index
fn cursorToBufferIndex(eb: *EditBuffer, pos: usize) usize {
    if (pos == 0) return 0;

    // Assert the bytes are valid utf-8
    var iter = GraphemeIterator.init(eb.buffer.items) catch unreachable;
    var index: usize = 0;
    while (iter.next()) |grapheme| : (index += 1) {
        if (index == pos) {
            return grapheme.offset;
        }
    }

    return eb.buffer.items.len;
}

/// Converts a buffer index to a cursor position
pub fn bufferIndexToCursor(eb: *EditBuffer, index: usize) usize {
    if (index == 0) return 0;

    var iter = GraphemeIterator.init(eb.buffer.items) catch unreachable;
    var cursor: usize = 0;
    while (iter.next()) |grapheme| : (cursor += 1) {
        if (grapheme.offset == index) {
            return cursor;
        }
    }

    return eb.len;
}

/// Returns the length of utf-8 encoded text
fn utf8Len(bytes: []const u8) usize {
    // Assert the bytes are valid utf-8
    var iter = GraphemeIterator.init(bytes) catch unreachable;
    var len: usize = 0;
    while (iter.next()) |_| len += 1;
    return len;
}

test "EditBuffer uft8Len" {
    try testing.expectEqual(@as(usize, 0), EditBuffer.utf8Len(""));
    try testing.expectEqual(@as(usize, 1), EditBuffer.utf8Len("a"));
    try testing.expectEqual(@as(usize, 1), EditBuffer.utf8Len("é"));
    try testing.expectEqual(@as(usize, 1), EditBuffer.utf8Len("🙃"));
    try testing.expectEqual(@as(usize, 1), EditBuffer.utf8Len("ᄒ"));
    // US flag consists of 2 individual multi-byte codepoints
    try testing.expectEqual(@as(usize, 1), EditBuffer.utf8Len("🇺🇸"));
    // Polar bear consists of 4 individual multi-byte codepoints
    try testing.expectEqual(@as(usize, 1), EditBuffer.utf8Len("🐻‍❄️"));
}

test "EditBuffer insert" {
    var eb = EditBuffer.init(testing.allocator);
    defer eb.deinit();

    try testing.expectEqual(@as(usize, 0), eb.cursor);
    try eb.insert("z");
    try testing.expectEqualStrings("z", eb.slice());
    try eb.insert("i");
    try testing.expectEqualStrings("zi", eb.slice());
    try eb.insert("g");
    try testing.expectEqualStrings("zig", eb.slice());

    try eb.insert(" ⚡ ");
    try testing.expectEqualStrings("zig ⚡ ", eb.slice());
    try eb.insert("¯\\_(ツ)_/¯");
    try testing.expectEqualStrings("zig ⚡ ¯\\_(ツ)_/¯", eb.slice());
    try eb.insert(" ¾");
    try testing.expectEqualStrings("zig ⚡ ¯\\_(ツ)_/¯ ¾", eb.slice());
    try testing.expectEqual(@as(usize, 17), EditBuffer.utf8Len(eb.slice()));
}

test "EditBuffer set and move cursor" {
    var eb = EditBuffer.init(testing.allocator);
    defer eb.deinit();

    try eb.insert("Ä is for Äpfel 🍎, B is for Bear 🧸");

    // test clamping
    eb.setCursor(10000);
    try testing.expectEqual(@as(usize, 33), eb.cursor);
    eb.setCursor(0);
    try testing.expectEqual(@as(usize, 0), eb.cursor);

    // insert at the beginning
    try eb.insert("The Alphabet: ");
    try testing.expectEqualStrings("The Alphabet: Ä is for Äpfel 🍎, B is for Bear 🧸", eb.slice());

    // insert at the end
    eb.setCursor(eb.len);
    try eb.insert(" ...");
    try testing.expectEqualStrings("The Alphabet: Ä is for Äpfel 🍎, B is for Bear 🧸 ...", eb.slice());

    // relative movement
    eb.setCursor(0);
    eb.moveCursor(4, .right);
    try eb.insert("Awesome 💥 ");
    try testing.expectEqualStrings("The Awesome 💥 Alphabet: Ä is for Äpfel 🍎, B is for Bear 🧸 ...", eb.slice());

    // clamping
    eb.moveCursor(100000, .right);
    try testing.expectEqual(@as(usize, 61), eb.cursor);
    eb.moveCursor(100000, .left);
    try testing.expectEqual(@as(usize, 0), eb.cursor);
}

test "EditBuffer deletion" {
    var eb = EditBuffer.init(testing.allocator);
    defer eb.deinit();

    try eb.insert("Pokémon 😁 → more ascii here 🤯");

    // test bounds
    eb.setCursor(0);
    eb.delete(1, .left);
    eb.setCursor(eb.len);
    eb.delete(1, .right);
    try testing.expectEqualStrings("Pokémon 😁 → more ascii here 🤯", eb.slice());

    eb.setCursor(0);
    eb.delete(1, .right);
    eb.setCursor(eb.len);
    eb.delete(2, .left);
    try testing.expectEqualStrings("okémon 😁 → more ascii here", eb.slice());

    eb.setCursor(0);
    eb.deleteTo(7);
    try testing.expectEqualStrings("😁 → more ascii here", eb.slice());

    eb.setCursor(4);
    eb.deleteTo(0);
    try testing.expectEqualStrings("more ascii here", eb.slice());

    eb.setCursor(eb.len);
    eb.deleteTo(0);
    try testing.expectEqualStrings("", eb.slice());
}
