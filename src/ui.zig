const std = @import("std");
const system = std.os.linux;

const ArrayList = std.ArrayList;
const File = std.fs.File;

const filter = @import("filter.zig");

const TIOCGWINSZ = 0x5413;

pub const Terminal = struct {
    tty: File,
    termios: std.os.termios,
    raw_termios: std.os.termios,

    pub fn init() !Terminal {
        var tty = try std.fs.openFileAbsolute("/dev/tty", .{ .read = true, .write = true });

        // store original terminal settings to restore later
        var termios = try std.os.tcgetattr(tty.handle);
        var raw_termios = termios;

        raw_termios.iflag &= ~@as(u32, system.ICRNL);
        raw_termios.lflag &= ~@as(u32, system.ICANON | system.ECHO);
        raw_termios.cc[system.V.MIN] = 0;
        raw_termios.cc[system.V.TIME] = 1;

        try std.os.tcsetattr(tty.handle, .NOW, raw_termios);

        return Terminal{ .tty = tty, .termios = termios, .raw_termios = raw_termios };
    }

    pub fn deinit(self: *Terminal) void {
        std.os.tcsetattr(self.tty.handle, .NOW, self.termios) catch {};
        self.tty.close();
    }

    fn write(self: *Terminal, args: anytype) void {
        std.fmt.format(self.tty.writer(), "\x1b[{d}{c}", args) catch unreachable;
    }

    pub fn clearLine(self: *Terminal) void {
        self.write(.{ 0, 'G' });
        self.write(.{ 2, 'K' });
    }

    pub fn lineUp(self: *Terminal) void {
        self.write(.{ 1, 'A' });
    }

    pub fn lineDown(self: *Terminal) void {
        self.write(.{ 1, 'B' });
    }

    pub fn cursorVisible(self: *Terminal, show: bool) void {
        if (show) {
            self.write(.{ 25, 'h' });
        } else {
            self.write(.{ 25, 'l' });
        }
    }

    pub fn sgr(self: *Terminal, code: usize) void {
        self.write(.{ code, 'm' });
    }

    const WinSize = struct {
        x: usize,
        y: usize,
    };

    pub fn windowSize(self: *Terminal) ?WinSize {
        var size: std.os.linux.winsize = undefined;

        if (std.os.linux.ioctl(self.tty.handle, TIOCGWINSZ, @ptrToInt(&size)) == -1) {
            return null;
        }

        return WinSize{ .x = size.ws_col, .y = size.ws_row };
    }
};

const Key = union(enum) {
    character: u8,
    control: u8,
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

    // control chars
    if (std.ascii.isCntrl(byte)) return .{ .control = byte };

    // ascii chars
    if (std.ascii.isPrint(byte)) return .{ .character = byte };

    return .none;
}

// the number of rows of output
const numRows: usize = 10;

const State = struct {
    cursor: usize,
    selected: usize,
};

fn draw(terminal: *Terminal, state: *State, query: ArrayList(u8), candidates: ArrayList(filter.Candidate)) !void {
    const win_size = terminal.windowSize();

    terminal.cursorVisible(false);
    terminal.clearLine();

    // draw the candidates
    const lines = numRows;
    var i: usize = 0;
    while (i < lines) : (i += 1) {
        terminal.lineDown();
        terminal.clearLine();
        if (i == state.selected) {
            terminal.sgr(7);
        } else {
            terminal.sgr(0);
        }
        if (i < candidates.items.len) {
            var str = candidates.items[i].str[0..std.math.min(win_size.?.x, candidates.items[i].str.len)];
            try std.fmt.format(terminal.tty.writer(), "{s}\r", .{str});
        }
        if (i == state.selected) terminal.sgr(0);
    }
    terminal.sgr(0);
    i = 0;
    while (i < lines) : (i += 1) {
        terminal.lineUp();
    }

    // draw the prompt
    try std.fmt.format(terminal.tty.writer(), "> {s}\r", .{query.items});

    // move cursor by drawing chars
    _ = try terminal.tty.writer().write("> ");
    for (query.items) |c, index| {
        if (index == state.cursor) break;
        _ = try terminal.tty.writer().writeByte(c);
    }

    terminal.cursorVisible(true);
}

fn ctrl(comptime key: u8) u8 {
    return key & 0x1f;
}

pub fn run(allocator: std.mem.Allocator, terminal: *Terminal, candidates: ArrayList(filter.Candidate)) !?ArrayList(u8) {
    var query = ArrayList(u8).init(allocator);
    defer query.deinit();

    var state = State{
        .cursor = 0,
        .selected = 0,
    };

    // ensure enough room to draw all `numRows` lines of output by drawing blank lines
    // effectively scrolling the view
    {
        var i: usize = 0;
        while (i < numRows) : (i += 1) {
            _ = try terminal.tty.writer().write("\n");
        }
        i = 0;
        while (i < numRows) : (i += 1) terminal.lineUp();
    }

    var should_draw = true;
    while (true) {
        var filtered = try filter.filter(allocator, candidates.items, query.items);
        defer filtered.deinit();

        // var sorted = std.sort.sort(filter.Candidate, candidates.items, {}, filter.sort);

        if (should_draw) try draw(terminal, &state, query, filtered);
        should_draw = false;

        const visible_rows = std.math.min(numRows, filtered.items.len);

        var key = readKey(terminal.tty);
        switch (key) {
            .character => |byte| {
                try query.insert(state.cursor, byte);
                state.cursor += 1;
                should_draw = true;
            },
            .control => |byte| {
                switch (byte) {
                    ctrl('u') => {
                        state.cursor = 0;
                        query.clearAndFree();
                        should_draw = true;
                    },
                    ctrl('p') => if (state.selected > 0) {
                        state.selected -= 1;
                        should_draw = true;
                    },
                    ctrl('n') => if (state.selected < visible_rows - 1) {
                        state.selected += 1;
                        should_draw = true;
                    },
                    else => {},
                }
            },
            .backspace => {
                if (query.items.len > 0 and state.cursor == query.items.len) {
                    _ = query.pop();
                    state.cursor -= 1;
                    should_draw = true;
                } else if (query.items.len > 0 and state.cursor > 0) {
                    _ = query.orderedRemove(state.cursor);
                    state.cursor -= 1;
                    should_draw = true;
                }
            },
            .delete => {
                if (query.items.len > 0 and state.cursor < query.items.len) {
                    _ = query.orderedRemove(state.cursor);
                    should_draw = true;
                }
            },
            .up => if (state.selected > 0) {
                state.selected -= 1;
                should_draw = true;
            },
            .down => if (state.selected < visible_rows - 1) {
                state.selected += 1;
                should_draw = true;
            },
            .left => if (state.cursor > 0) {
                state.cursor -= 1;
                should_draw = true;
            },
            .right => if (state.cursor < query.items.len) {
                state.cursor += 1;
                should_draw = true;
            },
            .enter => {
                if (filtered.items.len == 0) break;

                var selected = ArrayList(u8).init(allocator);
                try selected.appendSlice(filtered.items[state.selected].str);
                return selected;
            },
            .esc => break,
            .none => {},
        }
    }

    return null;
}

pub fn cleanUp(terminal: *Terminal) !void {
    // offset to handle prompt line
    const lines = numRows;
    var i: usize = 0;
    while (i < lines) : (i += 1) {
        terminal.clearLine();
        terminal.lineDown();
    }
    i = 0;
    while (i < lines) : (i += 1) {
        terminal.lineUp();
    }
}
