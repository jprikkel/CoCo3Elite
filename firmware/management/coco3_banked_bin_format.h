#ifndef COCO3ELITE_COCO3_BANKED_BIN_FORMAT_H
#define COCO3ELITE_COCO3_BANKED_BIN_FORMAT_H

#include <stdint.h>

#define COCO3_BANKED_BIN_HEADER_SIZE 16u

typedef int (*coco3_banked_read_byte_fn)(void *context, uint8_t *value);

struct coco3_banked_bin_info {
    uint16_t execution_descriptor;
    uint32_t payload_bytes;
    uint16_t data_records;
};

enum coco3_banked_bin_result {
    COCO3_BANKED_BIN_OK = 0,
    COCO3_BANKED_BIN_NOT_FORMAT = 1,
    COCO3_BANKED_BIN_TRUNCATED = 2,
    COCO3_BANKED_BIN_BAD_HEADER = 3,
    COCO3_BANKED_BIN_BAD_RECORD = 4,
    COCO3_BANKED_BIN_BAD_LENGTH = 5,
    COCO3_BANKED_BIN_BAD_CRC = 6,
    COCO3_BANKED_BIN_MISSING_DATA = 7
};

/* Validate the generic C3B1 container and its banked placement records.
 * The callback starts at file offset zero and is consumed sequentially. */
int coco3_banked_bin_validate(coco3_banked_read_byte_fn read_byte,
                              void *context, uint32_t file_size,
                              struct coco3_banked_bin_info *info);

#endif
