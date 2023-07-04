//! A simple event loop that tracks signals and tty input based on pselect(2)
//!
//! Because pselect is difficult to call from Zig, a portion of the code is written in C.
//! See loop.c for more details.

const builtin = @import("builtin");
const os = std.os;
const std = @import("std");

const Loop = @This();

const SIG_BLOCK = if (builtin.os.tag == .macos) os.SIG._BLOCK else os.SIG.BLOCK;

/// The file descriptor of the TTY
ttyfd: os.fd_t,

/// The file descriptor of the child process stdout
child_out: ?os.fd_t = null,

/// The file descriptor of the child process stderr
child_err: ?os.fd_t = null,

/// A simple list of any pending events
/// There will never be more than pending 3 events, so a static buffer is sufficient
pending: [3]?os.fd_t = .{ null, null, null },

/// Because the default for SIGWINCH is to discard the signal, all this
/// handler needs to do is exist for the signal to no longer be ignored.
fn handler(_: c_int) align(1) callconv(.C) void {}

pub fn init(ttyfd: os.fd_t) !Loop {
    // Block handling of SIGWINCH.
    // This will be unblocked by the kernel within the pselect() call.
    var sigset = os.system.empty_sigset;
    os.system.sigaddset(&sigset, os.SIG.WINCH);
    _ = os.system.sigprocmask(SIG_BLOCK, &sigset, null);

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

pub fn setChild(loop: *Loop, outfd: os.fd_t, errfd: os.fd_t) void {
    loop.child_out = outfd;
    loop.child_err = errfd;
}

/// This function is defined in loop.c
extern "c" fn wait_internal(fds: [*]const c_int, nfds: c_int, ready: [*]c_int) c_int;

/// Wait for an event
///
/// An event is either a file descriptor available to read, or a resize.
pub fn wait(loop: *Loop) Event {

    // Handle any pending events first
    for (loop.pending, 0..) |fdOrNull, index| {
        if (fdOrNull) |fd| {
            loop.pending[index] = null;
            if (fd == loop.ttyfd) return .tty;
            if (fd == loop.child_out) return .child_out;
            if (fd == loop.child_err) return .child_err;
        }
    }

    // Wait for events
    const fds: [3]os.fd_t = .{ loop.ttyfd, loop.child_out orelse 0, loop.child_err orelse 0 };
    const has_child = loop.child_out != null;

    var ready: [3]os.fd_t = undefined;
    const num_ready = wait_internal(&fds, if (has_child) 3 else 1, &ready);
    if (num_ready == -1) {
        return .resize;
    }

    // It is possible for multiple events to occur, so add all to pending array
    for (ready[0..@intCast(num_ready)], 0..) |fd, i| {
        loop.pending[i] = fd;
    }

    return loop.wait();
}

const Event = union(enum) {
    tty,
    resize,
    child_out,
    child_err,
};
