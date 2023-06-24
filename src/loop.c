// Using pselect() from Zig is tricky due to macros not working with translate-c
// so we write the interface to pselect() in C and then call this function from Zig

#include <stdlib.h>

#include <signal.h>
#include <sys/errno.h>
#include <sys/select.h>

int wait_internal(int ttyfd) {

    fd_set read_set;
    FD_ZERO(&read_set);
    FD_SET(ttyfd, &read_set);

    // Create a set that only allows SIGWINCH through
    sigset_t sigwinch_set;
    sigfillset(&sigwinch_set);
    sigdelset(&sigwinch_set, SIGWINCH);

    if (pselect(ttyfd + 1, &read_set, NULL, NULL, NULL, &sigwinch_set) == -1) {
        // The only signals that can get through are SIGKILL, SIGSTOP, and SIGWINCH.
        // The first two will kill the program no matter what we do, so we assume
        // the signal is SIGWINCH. If it is we redraw, otherwise zf will exit.
        if (errno == EINTR) {
            return -1;
        }
    }

    if (FD_ISSET(ttyfd, &read_set)) {
        return ttyfd;
    }

    // Some unreachable error occurred
    return -2;
}
