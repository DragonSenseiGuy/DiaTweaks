#include "Write.h"
#include "Split.h"
#include <errno.h>
#include <poll.h>
#include <stdlib.h>
#include <time.h>

static DPSendResult DPSendAll(int fd, const uint8_t *data, size_t length, int flags, DPSendFunction send, bool checkSecondary) {
    uint64_t deadline = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) + 1000000000ULL;
    for (size_t sent = 0; sent < length;) {
        DPSendResult result = send(fd, data + sent, length - sent, flags, NULL, 0);
        if (result.sent >= 0 && result.secondary && checkSecondary) return errno = ECONNRESET, (DPSendResult){ -1, 0 };
        if (result.sent > 0) {
            sent += (size_t)result.sent;
            continue;
        }
        if (result.sent == 0) return sent ? (errno = ECONNRESET, (DPSendResult){ -1, 0 }) : result;
        if (errno == EINTR) continue;
        if (errno != EAGAIN || !sent) return result;
        uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        if (now >= deadline) return errno = ETIMEDOUT, (DPSendResult){ -1, 0 };
        struct pollfd ready = { fd, POLLOUT, 0 };
        if (poll(&ready, 1, (int)((deadline - now) / 1000000) + 1) < 0 && errno != EINTR) return (DPSendResult){ -1, 0 };
    }
    return (DPSendResult){ (ssize_t)length, 0 };
}

static bool DPHasRoom(int fd, size_t length) {
    int type = 0, buffer = 0, queued = 0;
    socklen_t size = sizeof type, bufferSize = sizeof buffer, queuedSize = sizeof queued;
    return getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &size) == 0 && type == SOCK_STREAM
        && getsockopt(fd, SOL_SOCKET, SO_SNDBUF, &buffer, &bufferSize) == 0
        && getsockopt(fd, SOL_SOCKET, SO_NWRITE, &queued, &queuedSize) == 0 && buffer >= 0 && queued >= 0
        && (size_t)buffer >= (size_t)queued && (size_t)buffer - (size_t)queued >= length;
}

bool DPSendSplit(int fd, const uint8_t *data, size_t length, int flags, uint32_t random, DPSendFunction send,
                 bool checkSecondary, DPSendResult *result) {
    if (!data || length > SIZE_MAX - 5) return false;
    uint8_t stack[4096];
    uint8_t *out = length <= sizeof stack - 5 ? stack : malloc(length + 5);
    size_t split = out ? DPSplitHello(data, length, out, random) : 0;
    if (!split || !DPHasRoom(fd, split)) {
        if (out != stack) free(out);
        return false;
    }
    *result = DPSendAll(fd, out, split, flags, send, checkSecondary);
    if (out != stack) {
        int error = errno;
        free(out);
        errno = error;
    }
    if (result->sent > 0) *result = (DPSendResult){ (ssize_t)length, 0 };
    return true;
}
