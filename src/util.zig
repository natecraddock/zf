const std = @import("std");
const ArrayList = std.ArrayList;

/// read from a file into an ArrayList.
/// similar to readAllAlloc from the standard library, but
/// will read until out of memory rather than limiting to a
/// maximum size.
pub fn readAll(reader: *std.fs.File.Reader, array_list: *ArrayList(u8)) !void {
    // ensure the array starts at a decent size
    try array_list.ensureTotalCapacity(4096);

    var index: usize = 0;
    while (true) {
        array_list.expandToCapacity();
        const slice = array_list.items[index..];
        const read = try reader.readAll(slice);
        index += read;

        if (read != slice.len) {
            array_list.shrinkAndFree(index);
            return;
        }

        try array_list.ensureTotalCapacity(index + 1);
    }
}
