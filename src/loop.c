// Using pselect() from Zig is tricky due to macros not working with translate-c
// so we write the interface to pselect() in C and then call this function from Zig

#include <stdlib.h>

#include <signal.h>
#include <sys/errno.h>
#include <sys/select.h>


int wait_internal(const int *fds, int nfds, int *ready) {
    fd_set read_set;
    FD_ZERO(&read_set);

    int max_fd = -1;
    for (int i = 0; i < nfds; i++) {
        FD_SET(fds[i], &read_set);
        if (fds[i] > max_fd) {
            max_fd = fds[i];
        }
    }

    // Create a set that only allows SIGWINCH through
    sigset_t sigwinch_set;
    sigfillset(&sigwinch_set);
    sigdelset(&sigwinch_set, SIGWINCH);

    if (pselect(max_fd + 1, &read_set, NULL, NULL, NULL, &sigwinch_set) == -1) {
        return -1;
    }

    int num_ready = 0;
    for (int i = 0; i < nfds; i++) {
        if (FD_ISSET(fds[i], &read_set)) {
            ready[num_ready] = fds[i];
            num_ready += 1;
        }
    }

    return num_ready;
}
