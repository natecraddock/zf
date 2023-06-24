//! A simple event loop that tracks signals and tty input based on pselect(2)
//!
//! Because pselect is difficult to call from Zig, a portion of the code is written in C.
//! See loop.c for more details.

const os = std.os;
const std = @import("std");

const Loop = @This();

/// The file descriptor of the TTY
ttyfd: os.fd_t,

/// Because the default for SIGWINCH is to discard the signal, all this
/// handler needs to do is exist for the signal to no longer be ignored.
fn handler(_: c_int) align(1) callconv(.C) void {}

pub fn init(ttyfd: os.fd_t) !Loop {
    // Block handling of SIGWINCH.
    // This will be unblocked by the kernel within the pselect() call.
    var sigset = os.system.empty_sigset;
    os.system.sigaddset(&sigset, os.SIG.WINCH);
    _ = os.system.sigprocmask(os.SIG._BLOCK, &sigset, null);

    // Setup SIGWINCH signal handler
    var sigaction: os.Sigaction = .{
        .handler = .{ .handler = handler },
        .mask = os.system.empty_sigset,
        .flags = os.SA.RESTART,
    };
    try os.sigaction(os.SIG.WINCH, &sigaction, null);

    return .{ .ttyfd = ttyfd };
}

pub fn deinit(loop: *Loop) void {
    _ = loop;
}

/// This function is defined in loop.c
extern "c" fn wait_internal(ttyfd: c_int) c_int;

/// Wait for an event
///
/// An event is either a file descriptor available to read, or a resize.
pub fn wait(loop: *Loop) !Event {
    const fd = wait_internal(loop.ttyfd);

    if (fd == loop.ttyfd) {
        return .tty;
    } else if (fd == -1) {
        return .resize;
    } else unreachable;
}

const Event = union(enum) {
    tty,
    resize,
};
