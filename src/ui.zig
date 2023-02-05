const dw = ziglyph.display_width;
const filter = @import("filter.zig");
const std = @import("std");
const system = std.os.system;
const testing = std.testing;
const ziglyph = @import("ziglyph");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Candidate = filter.Candidate;
const EditBuffer = @import("EditBuffer.zig");
const Range = filter.Range;
const Terminal = term.Terminal;

const term = @import("term.zig");

const State = struct {
    selected: usize,
    prompt: []const u8,
    prompt_width: usize,
};

const HighlightSlice = struct {
    str: []const u8,
    highlight: bool,
};

const Slicer = struct {
    index: usize = 0,
    str: []const u8,
    ranges: []Range,

    fn init(str: []const u8, ranges: []Range) Slicer {
        return .{
            .str = str,
            .ranges = ranges,
        };
    }

    fn nextRange(slicer: *Slicer) ?*Range {
        var next_range: ?*Range = null;
        for (slicer.ranges) |*r| {
            if (r.start >= slicer.index) {
                if (next_range == null or r.start < next_range.?.start) {
                    next_range = r;
                } else if (r.start == next_range.?.start and r.end > next_range.?.end) {
                    next_range = r;
                }
            }
        }
        return next_range;
    }

    fn next(slicer: *Slicer) ?HighlightSlice {
        if (slicer.index >= slicer.str.len) return null;

        var highlight = false;
        const str = if (slicer.nextRange()) |range| blk: {
            // next highlight range past the visible end of the string
            if (range.start >= slicer.str.len) {
                break :blk slicer.str[slicer.index..];
            }

            if (slicer.index == range.start) {
                // inside highlight range
                highlight = true;
                break :blk slicer.str[range.start..std.math.min(slicer.str.len, range.end + 1)];
            } else {
                // before a highlight range
                break :blk slicer.str[slicer.index..std.math.min(slicer.str.len, range.start)];
            }
        } else slicer.str[slicer.index..];

        slicer.index += str.len;
        return HighlightSlice{ .str = str, .highlight = highlight };
    }
};

fn computeRanges(
    str: []const u8,
    filenameOrNull: ?[]const u8,
    ranges: []Range,
    tokens: [][]const u8,
    smart_case: bool,
) []Range {
    for (tokens) |token, i| {
        ranges[i] = filter.highlightToken(str, filenameOrNull, token, smart_case);
    }
    return ranges[0..tokens.len];
}

// Slices a string to be no longer than the specified width while considering graphemes and display width
fn graphemeWidthSlice(str: []const u8, width: usize) []const u8 {
    var iter = ziglyph.GraphemeIterator.init(str) catch unreachable;
    var current_width: usize = 0;
    while (iter.next()) |grapheme| {
        const grapheme_width = dw.strWidth(grapheme.bytes, .half) catch unreachable;
        if (current_width + grapheme_width > width) return str[0..grapheme.offset];
        current_width += grapheme_width;
    }
    return str;
}

inline fn drawCandidate(
    terminal: *Terminal,
    candidate: Candidate,
    tokens: [][]const u8,
    width: usize,
    selected: bool,
    smart_case: bool,
    plain: bool,
) void {
    if (selected) terminal.sgr(.reverse);
    defer terminal.sgr(.reset);

    var ranges_buf: [16]Range = undefined;
    const filename = if (plain) null else std.fs.path.basename(candidate.str);
    const ranges = computeRanges(candidate.str, filename, &ranges_buf, tokens, smart_case);

    const str_width = dw.strWidth(candidate.str, .half) catch unreachable;
    const str = graphemeWidthSlice(candidate.str, @min(width, str_width));

    // no highlights, just draw the string
    if (ranges.len == 0 or terminal.no_color) {
        _ = terminal.writer.write(str) catch unreachable;
    } else {
        var slicer = Slicer.init(str, ranges);
        while (slicer.next()) |slice| {
            if (slice.highlight) {
                terminal.sgr(terminal.highlight_color);
            } else {
                terminal.sgr(.default);
            }
            terminal.writeBytes(slice.str);
        }
    }
}

inline fn numDigits(number: usize) u16 {
    if (number == 0) return 1;
    return @intCast(u16, std.math.log10(number) + 1);
}

fn draw(
    terminal: *Terminal,
    state: *State,
    query: *EditBuffer,
    tokens: [][]const u8,
    candidates: []Candidate,
    total_candidates: usize,
    smart_case: bool,
    plain: bool,
) !void {
    const width = terminal.windowSize().?.x;

    // draw the candidates
    var line: usize = 0;
    while (line < terminal.height) : (line += 1) {
        terminal.cursorDown(1);
        terminal.clearLine();
        if (line < candidates.len) drawCandidate(terminal, candidates[line], tokens, width, line == state.selected, smart_case, plain);
    }
    terminal.sgr(.reset);
    terminal.cursorUp(terminal.height);

    // draw the prompt
    // TODO: handle display of queries longer than the screen width
    const query_width = try dw.strWidth(query.slice(), .half);
    terminal.clearLine();
    terminal.print("{s}{s}", .{ state.prompt, graphemeWidthSlice(query.slice(), std.math.min(width - state.prompt_width, query_width)) });

    // draw info if there is room
    const separator_width = 1;
    const spacing = @intCast(i32, width) - @intCast(i32, state.prompt_width + query_width + numDigits(candidates.len) + numDigits(total_candidates) + separator_width);
    if (spacing >= 1) {
        terminal.cursorRight(@intCast(usize, spacing));
        terminal.print("{}/{}", .{ candidates.len, total_candidates });
    }

    // position the cursor at the edit location
    terminal.cursorCol(0);
    const cursor_width = try dw.strWidth(query.sliceRange(0, query.cursor), .half);
    terminal.cursorRight(std.math.min(width - 1, cursor_width + state.prompt_width));

    try terminal.writer.flush();
}

const Action = union(enum) {
    str: []u8,
    line_up,
    line_down,
    cursor_left,
    cursor_leftmost,
    cursor_right,
    cursor_rightmost,
    backspace,
    delete,
    delete_word,
    delete_line,
    delete_line_forward,
    select,
    close,
    pass,
};

fn ctrl(comptime key: u8) u8 {
    return key & 0x1f;
}

// TODO: for some reason this needs to be extracted to a separate function,
// perhaps related to ziglang/zig#137
fn ctrlToAction(key: u8, vi_mode: bool) Action {
    return switch (key) {
        ctrl('c') => .close,
        ctrl('w') => .delete_word,
        ctrl('u') => .delete_line,
        ctrl('h') => .backspace,
        ctrl('a') => .cursor_leftmost,
        ctrl('e') => .cursor_rightmost,
        ctrl('d') => .delete,
        ctrl('f') => .cursor_right,
        ctrl('b') => .cursor_left,
        ctrl('p') => .line_up,
        ctrl('n'), ctrl('j') => .line_down,
        ctrl('k') => if (vi_mode) Action{ .line_up = {} } else Action{ .delete_line_forward = {} },
        else => .pass,
    };
}

fn inputToAction(input: term.InputBuffer, vi_mode: bool) Action {
    return switch (input) {
        .str => |bytes| {
            if (bytes.len == 0) return .pass;
            return .{ .str = bytes };
        },
        .control => |c| ctrlToAction(c, vi_mode),
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

/// split the query on spaces and return a slice of query tokens
pub fn splitQuery(query_tokens: [][]const u8, query: []const u8) [][]const u8 {
    var index: u8 = 0;
    var it = std.mem.tokenize(u8, query, " ");
    while (it.next()) |token| : (index += 1) {
        if (index == query_tokens.len) break;
        query_tokens[index] = token;
    }

    return query_tokens[0..index];
}

pub fn hasUpper(query: []const u8) bool {
    for (query) |c| {
        if (std.ascii.isUpper(c)) return true;
    }
    return false;
}

/// Escapes ANSI escape sequences in a given string and returns a new owned slice of bytes
/// representing the non-ANSI escape characters
///
/// Is not intended to cover the entirety of ANSI. Only a reasonable subset. More escaped
/// codes can be added as needed.
/// Currently escapes SGR sequences (\x1b[ ... m)
fn escapeANSI(allocator: Allocator, str: []const u8) ![]const u8 {
    const EscapeState = enum{
        esc,
        left_bracket,
        sgr,
    };

    var buf = try ArrayList(u8).initCapacity(allocator, str.len);
    var state: EscapeState = .esc;
    for (str) |byte| {
        switch (state) {
            .esc => switch (byte) {
                0x1b => state = .left_bracket,
                else => buf.appendAssumeCapacity(byte),
            },
            .left_bracket => switch (byte) {
                '[' => state = .sgr,
                else => state = .esc,
            },
            .sgr => switch (byte) {
                '0'...'9', ';' => continue,
                'm' => state = .esc,
                else => return error.UnknownANSIEscape,
            },
        }
    }

    return buf.toOwnedSlice();
}

fn testEscapeANSI(expected: []const u8, input: []const u8) !void {
    const escaped = try escapeANSI(testing.allocator, input);
    defer testing.allocator.free(escaped);
    try testing.expectEqualStrings(expected, escaped);
}

test "escape ANSI codes" {
    try testEscapeANSI("", "\x1b[0m");
    try testEscapeANSI("str", "\x1b[30mstr");
    try testEscapeANSI("contents", "\x1b[31mcontents\x1b[0m");
    try testEscapeANSI("abcd", "a\x1b[31mb\x1b[32mc\x1b[33md\x1b[0m");
}

pub fn run(
    allocator: Allocator,
    terminal: *Terminal,
    normalizer: ziglyph.Normalizer,
    candidates: []Candidate,
    keep_order: bool,
    plain: bool,
    prompt_str: []const u8,
    vi_mode: bool,
) !?[]const u8 {
    var query = EditBuffer.init(allocator);
    defer query.deinit();

    var state = State{
        .selected = 0,
        .prompt = prompt_str,
        .prompt_width = try dw.strWidth(try escapeANSI(allocator, prompt_str), .half),
    };

    // ensure enough room to draw all lines of output by drawing blank lines,
    // effectively scrolling the view. + 1 to also include the prompt's offset
    terminal.determineHeight();
    terminal.scrollDown(terminal.height);
    terminal.cursorUp(terminal.height);

    var filtered = candidates;

    var tokens_buf = try allocator.alloc([]const u8, 16);
    var tokens: [][]const u8 = splitQuery(tokens_buf, query.slice());
    var smart_case: bool = !hasUpper(query.slice());

    var redraw = true;

    while (true) {
        // did the query change?
        if (query.dirty) {
            query.dirty = false;

            tokens = splitQuery(tokens_buf, (try normalizer.nfd(allocator, query.slice())).slice);
            smart_case = !hasUpper(query.slice());

            filtered = try filter.rankCandidates(allocator, candidates, tokens, keep_order, plain, smart_case);
            redraw = true;
            state.selected = 0;
        }

        // do we need to redraw?
        if (redraw) {
            redraw = false;
            try draw(terminal, &state, &query, tokens, filtered, candidates.len, smart_case, plain);
        }

        const visible_rows = @intCast(i64, std.math.min(terminal.height, filtered.len));

        var buf: [2048]u8 = undefined;
        const input = try terminal.read(&buf);
        const action = inputToAction(input, vi_mode);

        const last_cursor = query.cursor;
        const last_selected = state.selected;

        switch (action) {
            .str => |str| try query.insert(str),
            .delete_word => if (query.len > 0) deleteWord(&query),
            .delete_line => query.deleteTo(0),
            .delete_line_forward => query.deleteTo(query.len),
            .backspace => query.delete(1, .left),
            .delete => query.delete(1, .right),
            .line_up => if (state.selected > 0) {
                state.selected -= 1;
            },
            .line_down => if (state.selected < visible_rows - 1) {
                state.selected += 1;
            },
            .cursor_left => query.moveCursor(1, .left),
            .cursor_leftmost => query.setCursor(0),
            .cursor_rightmost => query.setCursor(query.len),
            .cursor_right => query.moveCursor(1, .right),
            .select => {
                if (filtered.len == 0) break;
                return filtered[state.selected].str;
            },
            .close => break,
            .pass => {},
        }

        redraw = last_cursor != query.cursor or last_selected != state.selected;
    }

    return null;
}

/// Deletes a word to the left of the cursor. Words are separated by space or slash characters
fn deleteWord(query: *EditBuffer) void {
    var slice = query.slice()[0..query.cursorIndex()];
    var end = slice.len - 1;

    // ignore trailing spaces or slashes
    const trailing = slice[end];
    if (trailing == ' ' or trailing == '/') {
        while (end > 1 and slice[end] == trailing) {
            end -= 1;
        }
        slice = slice[0..end];
    }

    // find last most space or slash
    var last_index: ?usize = null;
    for (slice) |byte, i| {
        if (byte == ' ' or byte == '/') last_index = i;
    }

    if (last_index) |index| {
        query.deleteTo(query.bufferIndexToCursor(index + 1));
    } else query.deleteTo(0);
}
