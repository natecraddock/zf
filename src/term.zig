const std = @import("std");
const system = std.os.system;

const BufferedWriter = std.io.BufferedWriter;
const File = std.fs.File;

// Select Graphic Rendition (SGR) attributes
pub const SGRAttribute = enum(u8) {
    reset = 0,
    reverse = 7,

    black = 30,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    white = 37,
    default = 39,
    bright_black = 90,
    bright_red = 91,
    bright_green = 92,
    bright_yellow = 93,
    bright_blue = 94,
    bright_magenta = 95,
    bright_cyan = 96,
    bright_white = 97,
};

pub const Terminal = struct {
    tty: File,
    writer: BufferedWriter(4096, File.Writer),
    termios: std.os.termios,
    raw_termios: std.os.termios,

    height: usize = undefined,
    max_height: usize,

    no_color: bool,
    highlight_color: SGRAttribute,

    pub fn init(max_height: usize, highlight_color: SGRAttribute, no_color: bool) !Terminal {
        var tty = try std.fs.openFileAbsolute("/dev/tty", .{ .mode = .read_write });

        // store original terminal settings to restore later
        var termios = try std.os.tcgetattr(tty.handle);
        var raw_termios = termios;

        raw_termios.iflag &= ~@as(u32, system.ICRNL);
        raw_termios.lflag &= ~@as(u32, system.ICANON | system.ECHO | system.ISIG);

        try std.os.tcsetattr(tty.handle, .NOW, raw_termios);

        return Terminal{
            .tty = tty,
            .writer = std.io.bufferedWriter(tty.writer()),
            .termios = termios,
            .raw_termios = raw_termios,
            .max_height = max_height,
            .highlight_color = highlight_color,
            .no_color = no_color,
        };
    }

    pub fn nodelay(self: *Terminal, state: bool) void {
        self.raw_termios.cc[system.V.MIN] = if (state) 0 else 1;
        std.os.tcsetattr(self.tty.handle, .NOW, self.raw_termios) catch unreachable;
    }

    pub fn deinit(self: *Terminal) !void {
        var i: usize = 0;
        while (i < self.height) : (i += 1) {
            self.clearLine();
            self.cursorDown(1);
        }
        self.clearLine();
        self.cursorUp(self.height);

        try self.writer.flush();

        std.os.tcsetattr(self.tty.handle, .NOW, self.termios) catch return;
        self.tty.close();
    }

    pub fn determineHeight(self: *Terminal) void {
        const win_size = self.windowSize();
        self.height = std.math.clamp(self.max_height, 1, win_size.?.y - 1);
    }

    pub fn print(self: *Terminal, comptime str: []const u8, args: anytype) void {
        const writer = self.writer.writer();
        writer.print(str, args) catch unreachable;
    }

    fn write(self: *Terminal, args: anytype) void {
        const writer = self.writer.writer();
        writer.print("\x1b[{d}{c}", args) catch unreachable;
    }

    pub fn writeBytes(self: *Terminal, bytes: []const u8) void {
        const writer = self.writer.writer();
        _ = writer.write(bytes) catch unreachable;
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

    pub fn cursorUp(self: *Terminal, num: usize) void {
        self.write(.{ num, 'A' });
    }

    pub fn cursorDown(self: *Terminal, num: usize) void {
        self.write(.{ num, 'B' });
    }

    pub fn cursorRight(self: *Terminal, num: usize) void {
        if (num == 0) return;
        self.write(.{ num, 'C' });
    }

    pub fn cursorLeft(self: *Terminal, num: usize) void {
        self.write(.{ num, 'D' });
    }

    pub fn cursorCol(self: *Terminal, col: usize) void {
        self.write(.{ col, 'G' });
    }

    pub fn sgr(self: *Terminal, code: SGRAttribute) void {
        self.write(.{ @enumToInt(code), 'm' });
    }

    const WinSize = struct {
        x: usize,
        y: usize,
    };

    pub fn windowSize(self: *Terminal) ?WinSize {
        var size: system.winsize = undefined;

        if (system.ioctl(self.tty.handle, system.T.IOCGWINSZ, @ptrToInt(&size)) == -1) {
            return null;
        }

        return WinSize{ .x = size.ws_col, .y = size.ws_row };
    }
};
