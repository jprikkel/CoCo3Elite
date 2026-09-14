#ifndef COCO3ELITE_DECB_BIN_FORMAT_H
#define COCO3ELITE_DECB_BIN_FORMAT_H

#include <stdint.h>

// Transport-neutral validator for Disk Extended Color BASIC LOADM files.
// SD, serial, and Ethernet loaders can all supply the same byte callback.
typedef int (*decb_bin_read_byte_fn)(void *context, uint8_t *value);

struct decb_bin_info {
    uint16_t execution_address;
    uint32_t data_bytes;
    uint32_t stream_bytes;
    uint16_t data_records;
};

enum decb_bin_result {
    DECB_BIN_OK = 0,
    DECB_BIN_TRUNCATED = 1,
    DECB_BIN_BAD_RECORD = 2,
    DECB_BIN_BAD_LENGTH = 3,
    DECB_BIN_ADDRESS_WRAP = 4,
    DECB_BIN_IO_OVERLAP = 5,
    DECB_BIN_LOADER_OVERLAP = 6,
    DECB_BIN_MISSING_DATA = 7
};

int decb_bin_validate(decb_bin_read_byte_fn read_byte, void *context,
                      uint32_t file_size, struct decb_bin_info *info);

#endif
