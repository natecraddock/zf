const std = @import("std");
const system = std.os.linux;

const ArrayList = std.ArrayList;
const Candidate = filter.Candidate;
const File = std.fs.File;

const filter = @import("filter.zig");

// Select Graphic Rendition (SGR) attributes
const Attribute = enum(u8) {
    RESET = 0,
    REVERSE = 7,

    FG_CYAN = 36,
    FG_DEFAULT = 39,
};

pub const Terminal = struct {
    tty: File,
    writer: File.Writer,
    termios: std.os.termios,
    raw_termios: std.os.termios,

    height: usize = undefined,
    max_height: usize,

    pub fn init(max_height: usize) !Terminal {
        var tty = try std.fs.openFileAbsolute("/dev/tty", .{ .read = true, .write = true });

        // store original terminal settings to restore later
        var termios = try std.os.tcgetattr(tty.handle);
        var raw_termios = termios;

        raw_termios.iflag &= ~@as(u32, system.ICRNL);
        raw_termios.lflag &= ~@as(u32, system.ICANON | system.ECHO | system.ISIG);

        try std.os.tcsetattr(tty.handle, .NOW, raw_termios);

        return Terminal{
            .tty = tty,
            .writer = tty.writer(),
            .termios = termios,
            .raw_termios = raw_termios,
            .max_height = max_height,
        };
    }

    pub fn nodelay(self: *Terminal, state: bool) void {
        self.raw_termios.cc[system.V.MIN] = if (state) 0 else 1;
        std.os.tcsetattr(self.tty.handle, .NOW, self.raw_termios) catch unreachable;
    }

    pub fn deinit(self: *Terminal) void {
        std.os.tcsetattr(self.tty.handle, .NOW, self.termios) catch return;
        self.tty.close();
    }

    pub fn determineHeight(self: *Terminal) void {
        const win_size = self.windowSize();
        self.height = std.math.clamp(self.max_height, 1, win_size.?.y - 1);
    }

    fn write(self: *Terminal, args: anytype) void {
        self.writer.print("\x1b[{d}{c}", args) catch unreachable;
    }

    pub fn clearLine(self: *Terminal) void {
        self.cursorCol(1);
        self.write(.{ 2, 'K' });
    }

    pub fn scrollDown(self: *Terminal, num: usize) void {
        var i: usize = 0;
        while (i < num) : (i += 1) {
            _ = self.writer.write("\n") catch unreachable;
        }
    }

    pub fn lineUp(self: *Terminal, num: usize) void {
        self.write(.{ num, 'A' });
    }

    pub fn lineDown(self: *Terminal, num: usize) void {
        self.write(.{ num, 'B' });
    }

    pub fn cursorRight(self: *Terminal, num: usize) void {
        self.write(.{ num, 'C' });
    }

    pub fn cursorLeft(self: *Terminal, num: usize) void {
        self.write(.{ num, 'D' });
    }

    pub fn cursorCol(self: *Terminal, col: usize) void {
        self.write(.{ col, 'G' });
    }

    pub fn sgr(self: *Terminal, code: Attribute) void {
        self.write(.{ @enumToInt(code), 'm' });
    }

    const WinSize = struct {
        x: usize,
        y: usize,
    };

    pub fn windowSize(self: *Terminal) ?WinSize {
        var size: std.os.linux.winsize = undefined;

        if (std.os.linux.ioctl(self.tty.handle, std.os.system.T.IOCGWINSZ, @ptrToInt(&size)) == -1) {
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

fn readKey(terminal: *Terminal) Key {
    const reader = terminal.tty.reader();

    // reading may fail (timeout)
    var byte = reader.readByte() catch return .none;

    // escape
    if (byte == '\x1b') {
        terminal.nodelay(true);
        defer terminal.nodelay(false);

        var seq: [2]u8 = undefined;
        seq[0] = reader.readByte() catch return .esc;
        seq[1] = reader.readByte() catch return .esc;

        if (seq[0] == '[') {
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

const State = struct {
    cursor: usize,
    selected: usize,
};

fn highlightRanges(terminal: *Terminal, index: usize, ranges: []filter.Range) void {
    for (ranges) |*range| {
        if (index == range.start) {
            terminal.sgr(.FG_CYAN);
        } else if (index == range.end + 1) {
            terminal.sgr(.FG_DEFAULT);
        }
    }
}

inline fn drawCandidate(terminal: *Terminal, candidate: Candidate, width: usize, selected: bool) void {
    if (selected) terminal.sgr(.REVERSE);

    var str = candidate.str[0..std.math.min(width, candidate.str.len)];
    for (str) |c, i| {
        if (candidate.ranges != null) highlightRanges(terminal, i, candidate.ranges.?);
        terminal.writer.writeByte(c) catch unreachable;
    }

    terminal.sgr(.RESET);
}

inline fn numDigits(number: usize) u16 {
    if (number == 0) return 1;
    return @intCast(u16, std.math.log10(number) + 1);
}

fn draw(terminal: *Terminal, state: *State, query: ArrayList(u8), candidates: []Candidate, total_candidates: usize) !void {
    const width = terminal.windowSize().?.x;

    // draw the candidates
    var line: usize = 0;
    while (line < terminal.height) : (line += 1) {
        terminal.lineDown(1);
        terminal.clearLine();
        if (line < candidates.len) drawCandidate(terminal, candidates[line], width, line == state.selected);
    }
    terminal.sgr(.RESET);
    terminal.lineUp(terminal.height);

    // draw the prompt
    terminal.clearLine();
    try terminal.writer.print("> {s}", .{query.items[0..std.math.min(width - 2, query.items.len)]});

    // draw info if there is room
    const prompt_width = 2;
    const separator_width = 1;
    const spacing = @intCast(i32, width) - @intCast(i32, prompt_width + query.items.len + numDigits(candidates.len) + numDigits(total_candidates) + separator_width);
    if (spacing >= 1) {
        terminal.cursorRight(@intCast(usize, spacing));
        try terminal.writer.print("{}/{}", .{ candidates.len, total_candidates });
    }

    // position the cursor at the edit location
    terminal.cursorCol(1);
    terminal.cursorRight(std.math.min(width - 1, state.cursor + 2));
}

const Action = union(enum) {
    byte: u8,
    line_up,
    line_down,
    cursor_left,
    cursor_right,
    backspace,
    delete,
    delete_word,
    delete_line,
    select,
    close,
    pass,
};

fn ctrl(comptime key: u8) u8 {
    return key & 0x1f;
}

// TODO: for some reason this needs to be extracted to a separate function,
// perhaps related to ziglang/zig#137
fn ctrlToAction(key: u8) Action {
    return switch (key) {
        ctrl('c') => .close,
        ctrl('w') => .delete_word,
        ctrl('u') => .delete_line,
        ctrl('p') => .line_up,
        ctrl('n') => .line_down,
        else => .pass,
    };
}

fn keyToAction(key: Key) Action {
    return switch (key) {
        .character => |c| .{ .byte = c },
        .control => |c| ctrlToAction(c),
        .backspace => .backspace,
        .delete => .delete,
        .up => .line_up,
        .down => .line_down,
        .left => .cursor_left,
        .right => .cursor_right,
        .enter => .select,
        .esc => .close,
        .none => .pass,
    };
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

fn actionDeleteWord(query: *ArrayList(u8), cursor: *usize) void {
    if (cursor.* > 0) {
        const first_sep = charOrNull(query.items[cursor.* - 1]);
        while (first_sep != null and cursor.* > 0 and first_sep.? == query.items[cursor.* - 1]) {
            _ = query.pop();
            cursor.* -= 1;
        }
        while (cursor.* > 0) {
            _ = query.pop();
            cursor.* -= 1;
            if (cursor.* == 0) break;

            const sep = charOrNull(query.items[cursor.* - 1]);
            if (first_sep == null and sep != null) break;
            if (first_sep != null and sep != null and first_sep.? == sep.?) break;
        }
    }
}

pub fn run(
    allocator: std.mem.Allocator,
    terminal: *Terminal,
    candidates: []Candidate,
    keep_order: bool,
) !?[]const u8 {
    var query = ArrayList(u8).init(allocator);
    defer query.deinit();

    var state = State{
        .cursor = 0,
        .selected = 0,
    };

    // ensure enough room to draw all lines of output by drawing blank lines,
    // effectively scrolling the view. + 1 to also include the prompt's offset
    terminal.determineHeight();
    terminal.scrollDown(terminal.height);
    terminal.lineUp(terminal.height);

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

            filtered = try filter.rankCandidates(allocator, candidates, query.items, keep_order);
            redraw = true;
            state.selected = 0;
        }

        // did the selection move?
        if (redraw or state.cursor != old_state.cursor or state.selected != old_state.selected) {
            old_state = state;
            try draw(terminal, &state, query, filtered, candidates.len);
            redraw = false;
        }

        const visible_rows = std.math.min(terminal.height, filtered.len);

        const action = keyToAction(readKey(terminal));
        switch (action) {
            .byte => |b| {
                try query.insert(state.cursor, b);
                state.cursor += 1;
            },
            .delete_word => actionDeleteWord(&query, &state.cursor),
            .delete_line => {
                while (state.cursor > 0) {
                    _ = query.orderedRemove(state.cursor - 1);
                    state.cursor -= 1;
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
            .line_up => if (state.selected > 0) {
                state.selected -= 1;
            },
            .line_down => if (state.selected < visible_rows - 1) {
                state.selected += 1;
            },
            .cursor_left => if (state.cursor > 0) {
                state.cursor -= 1;
            },
            .cursor_right => if (state.cursor < query.items.len) {
                state.cursor += 1;
            },
            .select => {
                if (filtered.len == 0) break;
                return filtered[state.selected].str;
            },
            .close => break,
            .pass => {},
        }
    }

    return null;
}

pub fn cleanUp(terminal: *Terminal) !void {
    var i: usize = 0;
    while (i < terminal.height) : (i += 1) {
        terminal.clearLine();
        terminal.lineDown(1);
    }
    terminal.clearLine();
    terminal.lineUp(terminal.height);
}
