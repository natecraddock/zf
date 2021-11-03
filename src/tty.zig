const std = @import("std");
const bits = std.os.system;
const ArrayList = std.ArrayList;
const File = std.fs.File;

const filter = @import("filter.zig");

pub const Tty = struct {
    tty: File,
    termios: std.os.termios,
    raw_termios: std.os.termios,

    pub fn init() !Tty {
        var tty = try std.fs.openFileAbsolute("/dev/tty", .{ .read = true, .write = true });

        // store original terminal settings to restore later
        var termios = try std.os.tcgetattr(tty.handle);
        var raw_termios = termios;

        raw_termios.iflag &= ~@as(u32, bits.ICRNL);
        raw_termios.lflag &= ~@as(u32, bits.ICANON | bits.ECHO);
        raw_termios.cc[bits.VMIN] = 0;
        raw_termios.cc[bits.VTIME] = 1;

        try std.os.tcsetattr(tty.handle, .NOW, raw_termios);

        return Tty{ .tty = tty, .termios = termios, .raw_termios = raw_termios };
    }

    pub fn deinit(self: *Tty) void {
        std.os.tcsetattr(self.tty.handle, .NOW, self.termios) catch {};
        self.tty.close();
    }

    fn write(self: *Tty, args: anytype) void {
        std.fmt.format(self.tty.writer(), "\x1b[{d}{c}", args) catch unreachable;
    }

    pub fn clearLine(self: *Tty) void {
        self.write(.{ 0, 'G' });
        self.write(.{ 2, 'K' });
    }

    pub fn lineUp(self: *Tty) void {
        self.write(.{ 1, 'A' });
    }

    pub fn lineDown(self: *Tty) void {
        self.write(.{ 1, 'B' });
    }

    pub fn cursorVisible(self: *Tty, show: bool) void {
        if (show) {
            self.write(.{ 25, 'h' });
        } else {
            self.write(.{ 25, 'l' });
        }
    }
};

const Key = union(enum) {
    character: u8,
    esc,
    up,
    down,
    left,
    right,
    backspace,
    enter,
    none,
};

fn readKey(file: std.fs.File) Key {
    // reading may fail (timeout)
    var byte = file.reader().readByte() catch return .none;

    // escape
    if (byte == '\x1b') {
        var seq: [2]u8 = undefined;
        seq[0] = file.reader().readByte() catch return .esc;
        seq[1] = file.reader().readByte() catch return .esc;

        if (seq[0] == '[') {
            return switch (seq[1]) {
                'A' => .up,
                'B' => .down,
                'C' => .right,
                'D' => .left,
                else => .esc,
            };
        }

        return .esc;
    }

    switch (byte) {
        '\r' => return .enter,
        127 => return .backspace,
        else => {},
    }

    // regular chars
    if (std.ascii.isPrint(byte)) return .{ .character = byte };

    return .none;
}

fn draw(tty: *Tty, query: ArrayList(u8), options: ArrayList([]const u8)) !void {
    // tty.cursorVisible(false);
    tty.clearLine();

    // draw the options
    const lines = 10;
    var i: usize = 0;
    while (i < lines) : (i += 1) {
        tty.lineDown();
        tty.clearLine();
        if (i < options.items.len) {
            try std.fmt.format(tty.tty.writer(), "{s}\r", .{options.items[i]});
        }
    }
    i = 0;
    while (i < lines) : (i += 1) {
        tty.lineUp();
    }

    // draw the prompt
    _ = try tty.tty.writer().write("> ");
    _ = try tty.tty.writer().write(query.items);
    // try std.fmt.format(tty.tty.writer(), "> {s}\r", .{query.items});

    // tty.setCursor(1, 1);

    // tty.cursorVisible(true);
}

pub fn run(allocator: *std.mem.Allocator, tty: *Tty, options: ArrayList([]const u8)) !void {
    var query = ArrayList(u8).init(allocator);
    defer query.deinit();

    while (true) {
        var filtered = try filter.filter(allocator, options.items, query.items);
        defer filtered.deinit();

        try draw(tty, query, filtered);

        var key = readKey(tty.tty);
        switch (key) {
            .character => |byte| {
                if (byte == 'q') break;
                try query.append(byte);
            },
            .backspace => {
                if (query.items.len > 0) {
                    _ = query.pop();
                }
            },
            .up => {},
            .down => {},
            .left => {},
            .right => {},
            .enter => break,
            .esc => break,
            .none => {},
        }
    }
}
