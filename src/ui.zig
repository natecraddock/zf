const std = @import("std");
const system = std.os.linux;

const ArrayList = std.ArrayList;
const Candidate = filter.Candidate;
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
        raw_termios.lflag &= ~@as(u32, system.ICANON | system.ECHO | system.ISIG);
        raw_termios.cc[system.V.MIN] = 0;
        raw_termios.cc[system.V.TIME] = 1;

        try std.os.tcsetattr(tty.handle, .NOW, raw_termios);

        return Terminal{ .tty = tty, .termios = termios, .raw_termios = raw_termios };
    }

    pub fn deinit(self: *Terminal) void {
        std.os.tcsetattr(self.tty.handle, .NOW, self.termios) catch return;
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
const num_rows: usize = 10;

const State = struct {
    cursor: usize,
    selected: usize,
};

fn draw(terminal: *Terminal, state: *State, query: ArrayList(u8), candidates: []Candidate) !void {
    const win_size = terminal.windowSize();

    terminal.cursorVisible(false);
    terminal.clearLine();

    // draw the candidates
    const lines = num_rows;
    var i: usize = 0;
    while (i < lines) : (i += 1) {
        terminal.lineDown();
        terminal.clearLine();
        if (i == state.selected) {
            terminal.sgr(7);
        } else {
            terminal.sgr(0);
        }
        if (i < candidates.len) {
            var str = candidates[i].str[0..std.math.min(win_size.?.x, candidates[i].str.len)];
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

fn charOrNull(char: u8) ?u8 {
    // word separator chars for c-w word deletion
    const word_chars = " -_/.";
    const idx = std.mem.indexOfScalar(u8, word_chars, char);
    if (idx) |i| {
        return word_chars[i];
    }
    return null;
}

pub fn run(allocator: std.mem.Allocator, terminal: *Terminal, candidates: []Candidate) !?ArrayList(u8) {
    var query = ArrayList(u8).init(allocator);
    defer query.deinit();

    var state = State{
        .cursor = 0,
        .selected = 0,
    };

    // ensure enough room to draw all `num_rows` lines of output by drawing blank lines
    // effectively scrolling the view
    {
        var i: usize = 0;
        while (i < num_rows) : (i += 1) {
            _ = try terminal.tty.writer().write("\n");
        }
        i = 0;
        while (i < num_rows) : (i += 1) terminal.lineUp();
    }

    var filtered = candidates;

    var old_state = state;
    var old_query = try allocator.alloc(u8, query.items.len);

    var redraw = true;
    while (true) {
        // did the query change?
        if (!std.mem.eql(u8, query.items, old_query)) {
            allocator.free(old_query);
            old_query = try allocator.alloc(u8, query.items.len);
            std.mem.copy(u8, old_query, query.items);

            filtered = try filter.filter(allocator, candidates, query.items);
            redraw = true;
            state.selected = 0;
        }

        // did the selection move?
        // var sorted = std.sort.sort(Candidate, candidates.items, {}, filter.sort);
        if (redraw or state.cursor != old_state.cursor or state.selected != old_state.selected) {
            old_state = state;
            try draw(terminal, &state, query, filtered);
            redraw = false;
        }

        const visible_rows = std.math.min(num_rows, filtered.len);

        var key = readKey(terminal.tty);
        switch (key) {
            .character => |byte| {
                try query.insert(state.cursor, byte);
                state.cursor += 1;
            },
            .control => |byte| {
                switch (byte) {
                    // handle ctrl-c here rather than signals to allow for proper cleanup
                    ctrl('c') => break,
                    ctrl('w') => {
                        if (state.cursor > 0) {
                            const first_sep = charOrNull(query.items[state.cursor - 1]);
                            while (first_sep != null and state.cursor > 0 and first_sep.? == query.items[state.cursor - 1]) {
                                _ = query.pop();
                                state.cursor -= 1;
                            }
                            while (state.cursor > 0) {
                                _ = query.pop();
                                state.cursor -= 1;
                                if (state.cursor == 0) break;

                                const sep = charOrNull(query.items[state.cursor - 1]);
                                if (first_sep == null and sep != null) break;
                                if (first_sep != null and sep != null and first_sep.? == sep.?) break;
                            }
                        }
                    },
                    ctrl('u') => {
                        while (state.cursor > 0) {
                            _ = query.orderedRemove(state.cursor - 1);
                            state.cursor -= 1;
                        }
                    },
                    ctrl('p') => if (state.selected > 0) {
                        state.selected -= 1;
                    },
                    ctrl('n') => if (state.selected < visible_rows - 1) {
                        state.selected += 1;
                    },
                    else => {},
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
            .down => if (state.selected < visible_rows - 1) {
                state.selected += 1;
            },
            .left => if (state.cursor > 0) {
                state.cursor -= 1;
            },
            .right => if (state.cursor < query.items.len) {
                state.cursor += 1;
            },
            .enter => {
                if (filtered.len == 0) break;

                var selected = ArrayList(u8).init(allocator);
                try selected.appendSlice(filtered[state.selected].str);
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
    var i: usize = 0;
    while (i < num_rows) : (i += 1) {
        terminal.clearLine();
        terminal.lineDown();
    }
    terminal.clearLine();
    i = 0;
    while (i < num_rows) : (i += 1) {
        terminal.lineUp();
    }
}
