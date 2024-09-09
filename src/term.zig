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

pub const InputBuffer = union(enum) {
    str: []u8,
    control: u8,
    esc,
    up,
    down,
    left,
    right,
    backspace,
    delete,
    enter,
    tab,
    shift_tab,
    none,
};
