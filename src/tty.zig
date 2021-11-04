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

    pub fn sgr(self: *Tty, code: usize) void {
        self.write(.{ code, 'm' });
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
    delete,
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
            _ = file.reader().readByte() catch 0;

            return switch (seq[1]) {
                'A' => .up,
                'B' => .down,
                'C' => .right,
                'D' => .left,
                '3' => .delete,
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

    // ascii chars
    if (std.ascii.isPrint(byte) or std.ascii.isCntrl(byte)) return .{ .character = byte };

    return .none;
}

// the number of rows of output
const numRows: usize = 10;

const State = struct {
    cursor: usize,
    selected: usize,
};

fn draw(tty: *Tty, state: *State, query: ArrayList(u8), options: ArrayList([]const u8)) !void {
    tty.cursorVisible(false);
    tty.clearLine();

    // draw the options
    const lines = numRows;
    var i: usize = 0;
    while (i < lines) : (i += 1) {
        tty.lineDown();
        tty.clearLine();
        if (i == state.selected) {
            tty.sgr(7);
        } else {
            tty.sgr(0);
        }
        if (i < options.items.len) {
            try std.fmt.format(tty.tty.writer(), "{s}\r", .{options.items[i]});
        }
    }
    tty.sgr(0);
    i = 0;
    while (i < lines) : (i += 1) {
        tty.lineUp();
    }

    // draw the prompt
    try std.fmt.format(tty.tty.writer(), "> {s}\r", .{query.items});

    // move cursor by drawing chars
    _ = try tty.tty.writer().write("> ");
    for (query.items) |c, index| {
        if (index == state.cursor) break;
        _ = try tty.tty.writer().writeByte(c);
    }

    tty.cursorVisible(true);
}

fn ctrl(comptime key: u8) u8 {
    return key & 0x1f;
}

pub fn run(allocator: *std.mem.Allocator, tty: *Tty, options: ArrayList([]const u8)) !?ArrayList(u8) {
    var query = ArrayList(u8).init(allocator);
    defer query.deinit();

    var state = State{
        .cursor = 0,
        .selected = 0,
    };

    // ensure enough room to draw all `numRows` lines of output
    {
        var i: usize = 0;
        while (i < numRows) : (i += 1) {
            _ = try tty.tty.writer().write("\n");
        }
        i = 0;
        while (i < numRows) : (i += 1) tty.lineUp();
    }

    while (true) {
        var filtered = try filter.filter(allocator, options.items, query.items);
        defer filtered.deinit();

        try draw(tty, &state, query, filtered);

        var key = readKey(tty.tty);
        switch (key) {
            .character => |byte| {
                switch (byte) {
                    ctrl('u') => {
                        state.cursor = 0;
                        query.clearAndFree();
                    },
                    ctrl('p') => if (state.selected > 0) {
                        state.selected -= 1;
                    },
                    ctrl('n') => if (state.selected < numRows - 1) {
                        state.selected += 1;
                    },
                    else => {
                        try query.insert(state.cursor, byte);
                        state.cursor += 1;
                    },
                }
            },
            .backspace => {
                if (query.items.len > 0 and state.cursor == query.items.len) {
                    _ = query.pop();
                    state.cursor -= 1;
                } else if (query.items.len > 0 and state.cursor > 0) {
                    _ = query.orderedRemove(state.cursor);
                    state.cursor -= 1;
                }
            },
            .delete => {
                if (query.items.len > 0 and state.cursor < query.items.len) {
                    _ = query.orderedRemove(state.cursor);
                }
            },
            .up => if (state.selected > 0) {
                state.selected -= 1;
            },
            .down => if (state.selected < numRows - 1) {
                state.selected += 1;
            },
            .left => if (state.cursor > 0) {
                state.cursor -= 1;
            },
            .right => if (state.cursor < query.items.len) {
                state.cursor += 1;
            },
            .enter => {
                if (filtered.items.len == 0) break;

                var selected = ArrayList(u8).init(allocator);
                try selected.appendSlice(filtered.items[state.selected]);
                return selected;
            },
            .esc => break,
            .none => {},
        }
    }

    return null;
}

pub fn cleanUp(tty: *Tty) !void {
    // offset to handle prompt line
    const lines = numRows + 1;
    var i: usize = 0;
    while (i < lines) : (i += 1) {
        tty.clearLine();
        tty.lineDown();
    }
    i = 0;
    while (i < lines) : (i += 1) {
        tty.lineUp();
    }
}
