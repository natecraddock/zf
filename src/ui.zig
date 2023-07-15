const dw = ziglyph.display_width;
const filter = @import("filter.zig");
const std = @import("std");
const system = std.os.system;
const term = @import("term.zig");
const testing = std.testing;
const ziglyph = @import("ziglyph");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ArrayToggleSet = @import("array_toggle_set.zig").ArrayToggleSet;
const Candidate = filter.Candidate;
const EditBuffer = @import("EditBuffer.zig");
const Loop = @import("Loop.zig");
const Previewer = @import("Previewer.zig");
const Terminal = term.Terminal;

const sep = std.fs.path.sep;

const State = struct {
    selected: usize = 0,
    selected_rows: ArrayToggleSet(usize),
    offset: usize = 0,
    prompt: []const u8,
    prompt_width: usize,
    query: EditBuffer,
    redraw: bool = true,
    case_sensitive: bool = false,
    selection_changed: bool = false,
    preview: ?Previewer = null,
};

const HighlightSlicer = struct {
    matches: []const usize,
    highlight: bool,
    str: []const u8,
    index: usize = 0,

    const Slice = struct {
        str: []const u8,
        highlight: bool,
    };

    pub fn init(str: []const u8, matches: []const usize) HighlightSlicer {
        const highlight = std.mem.indexOfScalar(usize, matches, 0) != null;
        return .{ .str = str, .matches = matches, .highlight = highlight };
    }

    pub fn next(slicer: *HighlightSlicer) ?Slice {
        if (slicer.index >= slicer.str.len) return null;

        const start_state = slicer.highlight;
        var index: usize = slicer.index;
        while (index < slicer.str.len) : (index += 1) {
            const highlight = std.mem.indexOfScalar(usize, slicer.matches, index) != null;
            if (start_state != highlight) break;
        }

        const slice = Slice{ .str = slicer.str[slicer.index..index], .highlight = slicer.highlight };
        slicer.highlight = !slicer.highlight;
        slicer.index = index;
        return slice;
    }
};

fn calculateHighlights(
    str: []const u8,
    filenameOrNull: ?[]const u8,
    tokens: [][]const u8,
    case_sensitive: bool,
    plain: bool,
    matches: []usize,
) []usize {
    var index: usize = 0;
    for (tokens) |token| {
        const strict_path = !plain and filter.hasSeparator(token);
        const matched = filter.highlightToken(str, filenameOrNull, token, case_sensitive, strict_path, matches[index..]);
        index += matched.len;
    }

    return matches[0..index];
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
    highlight: bool,
    case_sensitive: bool,
    plain: bool,
) void {
    if (highlight) terminal.sgr(.reverse);
    defer terminal.sgr(.reset);

    var matches_buf: [2048]usize = undefined;
    const filename = if (plain) null else std.fs.path.basename(candidate.str);
    const matches = calculateHighlights(candidate.str, filename, tokens, case_sensitive, plain, &matches_buf);

    const str_width = dw.strWidth(candidate.str, .half) catch unreachable;
    const str = graphemeWidthSlice(candidate.str, @min(width - @as(usize, if (selected) 2 else 0), str_width));

    if (selected) {
        terminal.write("* ");
    }

    // no highlights, just output the string
    if (matches.len == 0 or terminal.no_color) {
        _ = terminal.write(str);
    } else {
        var slicer = HighlightSlicer.init(str, matches);
        while (slicer.next()) |slice| {
            if (slice.highlight) {
                terminal.sgr(terminal.highlight_color);
            } else {
                terminal.sgr(.default);
            }
            terminal.write(slice.str);
        }
    }
}

inline fn numDigits(number: usize) u16 {
    if (number == 0) return 1;
    return @intCast(std.math.log10(number) + 1);
}

fn draw(
    terminal: *Terminal,
    state: *State,
    tokens: [][]const u8,
    candidates: []Candidate,
    total_candidates: usize,
    plain: bool,
) !void {
    terminal.cursorVisible(false);
    const width = terminal.windowSize().?.x;

    // draw the candidates
    var line: usize = 0;
    while (line < terminal.height) : (line += 1) {
        terminal.cursorDown(1);
        terminal.cursorCol(0);
        if (line < candidates.len) drawCandidate(
            terminal,
            candidates[line + state.offset],
            tokens,
            width,
            state.selected_rows.contains(line + state.offset),
            line == state.selected,
            state.case_sensitive,
            plain,
        );
        terminal.clearToEndOfLine();
    }
    terminal.sgr(.reset);
    terminal.cursorUp(terminal.height);
    terminal.clearLine();

    // draw the stats
    const num_selected = state.selected_rows.slice().len;
    const stats_width = blk: {
        if (num_selected > 0) {
            const stats_width = numDigits(candidates.len) + numDigits(total_candidates) + numDigits(num_selected) + 4;
            terminal.cursorRight(width - stats_width);
            terminal.print("{}/{} [{}]", .{ candidates.len, total_candidates, num_selected });
            break :blk stats_width;
        } else {
            const stats_width = numDigits(candidates.len) + numDigits(total_candidates) + 1;
            terminal.cursorRight(width - stats_width);
            terminal.print("{}/{}", .{ candidates.len, total_candidates });
            break :blk stats_width;
        }
    };
    terminal.cursorCol(0);

    // draw the prompt
    // TODO: handle display of queries longer than the screen width
    const query_width = try dw.strWidth(state.query.slice(), .half);
    terminal.write(state.prompt);
    terminal.write(graphemeWidthSlice(state.query.slice(), @min(width - state.prompt_width - stats_width - 1, query_width)));

    // position the cursor at the edit location
    terminal.cursorCol(0);
    const cursor_width = try dw.strWidth(state.query.sliceRange(0, @min(width - state.prompt_width - stats_width - 1, state.query.cursor)), .half);
    terminal.cursorRight(@min(width - 1, cursor_width + state.prompt_width));

    terminal.cursorVisible(true);
    terminal.flush();
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
    select_up,
    select_down,
    confirm,
    close,
    pass,
};

fn ctrl(comptime key: u8) u8 {
    return key & 0x1f;
}

fn inputToAction(input: term.InputBuffer, vi_mode: bool) Action {
    return switch (input) {
        .str => |bytes| {
            if (bytes.len == 0) return .pass;
            return .{ .str = bytes };
        },
        .control => |c| switch (c) {
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
            ctrl('k') => if (vi_mode) .line_up else .delete_line_forward,
            else => .pass,
        },
        .backspace => .backspace,
        .delete => .delete,
        .up => .line_up,
        .down => .line_down,
        .left => .cursor_left,
        .right => .cursor_right,
        .enter => .confirm,
        .tab => .select_down,
        .shift_tab => .select_up,
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
    const EscapeState = enum {
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
    candidates: [][]const u8,
    keep_order: bool,
    plain: bool,
    preview_cmd: ?[]const u8,
    prompt_str: []const u8,
    vi_mode: bool,
) !?[]const []const u8 {
    // ensure enough room to draw all lines of output by drawing blank lines,
    // effectively scrolling the view. + 1 to also include the prompt's offset
    terminal.determineHeight();
    terminal.scrollDown(terminal.height);
    terminal.cursorUp(terminal.height);

    var filtered = blk: {
        var filtered = try ArrayList(Candidate).initCapacity(allocator, candidates.len);
        for (candidates) |candidate| {
            filtered.appendAssumeCapacity(.{ .str = candidate });
        }
        break :blk try filtered.toOwnedSlice();
    };
    var filtered_buf = try allocator.alloc(Candidate, candidates.len);

    var state = State{
        .selected = 0,
        .selected_rows = ArrayToggleSet(usize).init(allocator),
        .offset = 0,
        .prompt = prompt_str,
        .prompt_width = try dw.strWidth(try escapeANSI(allocator, prompt_str), .half),
        .query = EditBuffer.init(allocator),
    };

    var tokens_buf = try allocator.alloc([]const u8, 16);
    var tokens = splitQuery(tokens_buf, state.query.slice());

    var loop = try Loop.init(terminal.tty.handle);
    if (preview_cmd) |cmd| {
        state.preview = try Previewer.init(allocator, &loop, cmd, filtered[0].str);
    }

    while (true) {
        if (state.query.dirty) {
            state.query.dirty = false;

            tokens = splitQuery(tokens_buf, (try normalizer.nfd(allocator, state.query.slice())).slice);
            state.case_sensitive = hasUpper(state.query.slice());

            filtered = filter.rankCandidates(filtered_buf, candidates, tokens, keep_order, plain, state.case_sensitive);
            state.redraw = true;
            state.selected = 0;
            state.offset = 0;
            state.selected_rows.clear();
        }

        // The selection changed and the child process should be respawned
        if (state.selection_changed and state.preview != null) {
            state.selection_changed = false;
            try state.preview.?.spawn(filtered[state.selected + state.offset].str);
        }

        if (state.redraw) {
            state.redraw = false;
            try draw(terminal, &state, tokens, filtered, candidates.len, plain);
        }

        const event = loop.wait();
        switch (event) {
            .resize => state.redraw = true,
            .tty => {
                if (try handleInput(allocator, terminal, &state, filtered, vi_mode)) |selected| {
                    if (selected.len == 0) return null else return selected;
                }
            },
            .child_out => {
                try state.preview.?.read();
                state.redraw = true;
            },
            .child_err => {
                state.redraw = true;
            },
        }
    }
}

fn handleInput(allocator: Allocator, terminal: *Terminal, state: *State, filtered: []Candidate, vi_mode: bool) !?[]const []const u8 {
    var buf: [2048]u8 = undefined;
    const input = try terminal.read(&buf);
    const action = inputToAction(input, vi_mode);

    var query = &state.query;
    const last_cursor = query.cursor;
    const last_selected = state.selected;
    const last_offset = state.offset;

    const visible_rows = @min(terminal.height, filtered.len);

    switch (action) {
        .str => |str| try query.insert(str),
        .delete_word => if (query.len > 0) deleteWord(query),
        .delete_line => query.deleteTo(0),
        .delete_line_forward => query.deleteTo(query.len),
        .backspace => query.delete(1, .left),
        .delete => query.delete(1, .right),
        .line_up => lineUp(state),
        .line_down => lineDown(state, visible_rows, filtered.len - visible_rows),
        .cursor_left => query.moveCursor(1, .left),
        .cursor_leftmost => query.setCursor(0),
        .cursor_rightmost => query.setCursor(query.len),
        .cursor_right => query.moveCursor(1, .right),
        .select_up => {
            try state.selected_rows.toggle(state.selected + state.offset);
            lineUp(state);
            state.redraw = true;
        },
        .select_down => {
            try state.selected_rows.toggle(state.selected + state.offset);
            lineDown(state, visible_rows, filtered.len - visible_rows);
            state.redraw = true;
        },
        .confirm => {
            if (filtered.len == 0) return &.{};
            if (state.selected_rows.slice().len > 0) {
                var selected_buf = try allocator.alloc([]const u8, state.selected_rows.slice().len);
                for (state.selected_rows.slice(), 0..) |index, i| {
                    selected_buf[i] = filtered[index].str;
                }
                return selected_buf;
            }
            var selected_buf = try allocator.alloc([]const u8, 1);
            selected_buf[0] = filtered[state.selected + state.offset].str;
            return selected_buf;
        },
        .close => return &.{},
        .pass => {},
    }

    state.selection_changed = state.redraw or last_selected != state.selected or last_offset != state.offset or query.dirty;
    state.redraw = state.redraw or last_cursor != state.query.cursor or last_selected != state.selected or last_offset != state.offset;

    return null;
}

/// Deletes a word to the left of the cursor. Words are separated by space or slash characters
fn deleteWord(query: *EditBuffer) void {
    var slice = query.slice()[0..query.cursorIndex()];
    var end = slice.len - 1;

    // ignore trailing spaces or slashes
    const trailing = slice[end];
    if (trailing == ' ' or trailing == sep) {
        while (end > 1 and slice[end] == trailing) {
            end -= 1;
        }
        slice = slice[0..end];
    }

    // find last most space or slash
    var last_index: ?usize = null;
    for (slice, 0..) |byte, i| {
        if (byte == ' ' or byte == sep) last_index = i;
    }

    if (last_index) |index| {
        query.deleteTo(query.bufferIndexToCursor(index + 1));
    } else query.deleteTo(0);
}

fn lineUp(state: *State) void {
    if (state.selected > 0) {
        state.selected -= 1;
    } else if (state.offset > 0) {
        state.offset -= 1;
    }
}

fn lineDown(state: *State, visible_rows: usize, num_truncated: usize) void {
    if (state.selected < visible_rows - 1) {
        state.selected += 1;
    } else if (state.offset < num_truncated) {
        state.offset += 1;
    }
}
