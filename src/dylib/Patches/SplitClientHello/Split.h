#include <stddef.h>
#include <stdint.h>

// Writes a split ClientHello (length + 5 bytes) into out, or returns 0.
size_t DPSplitHello(const uint8_t *data, size_t length, uint8_t *out, uint32_t random);
