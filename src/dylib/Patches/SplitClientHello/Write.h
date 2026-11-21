#include <stdbool.h>
#include <stdint.h>
#include <sys/socket.h>

// macOS 13.3–26.0 checks sendto's second return register for a kernel bug; returning a pair lets us clear it.
typedef struct { ssize_t sent; uintptr_t secondary; } DPSendResult;
typedef DPSendResult (*DPSendFunction)(int fd, const void *buffer, size_t length, int flags, const struct sockaddr *address,
                                       socklen_t addressLength);

bool DPSendSplit(int fd, const uint8_t *data, size_t length, int flags, uint32_t random, DPSendFunction send,
                 bool checkSecondary, DPSendResult *result);
