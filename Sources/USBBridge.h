#ifndef USB_BRIDGE_H
#define USB_BRIDGE_H
#include <stdint.h>
typedef struct CaptureHandle CaptureHandle;
CaptureHandle *capture_open(char *error, int error_size);
CaptureHandle *capture_open_config(int hevc, int width, int height, int mbps, char *error, int error_size);
int capture_read(CaptureHandle *handle, uint8_t *buffer, int capacity);
void capture_close(CaptureHandle *handle);
#endif
// Fixed-argument adapter for Swift; POSIX shm_open is variadic on macOS.
int capture_shared_memory_open(const char *name);
