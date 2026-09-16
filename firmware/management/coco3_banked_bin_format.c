#include "coco3_banked_bin_format.h"

static uint32_t crc32_byte(uint32_t crc, uint8_t value)
{
    crc ^= value;
    for (uint8_t bit = 0; bit < 8; ++bit)
        crc = (crc >> 1) ^ ((crc & 1u) ? 0xedb88320u : 0u);
    return crc;
}

static int file_byte(coco3_banked_read_byte_fn read_byte, void *context,
                     uint32_t file_size, uint32_t *offset, uint8_t *value)
{
    if (*offset >= file_size || read_byte(context, value))
        return COCO3_BANKED_BIN_TRUNCATED;
    ++*offset;
    return COCO3_BANKED_BIN_OK;
}

static int payload_byte(coco3_banked_read_byte_fn read_byte, void *context,
                        uint32_t file_size, uint32_t payload_end,
                        uint32_t *offset, uint32_t *crc, uint8_t *value)
{
    int result;
    if (*offset >= payload_end)
        return COCO3_BANKED_BIN_BAD_LENGTH;
    result = file_byte(read_byte, context, file_size, offset, value);
    if (!result)
        *crc = crc32_byte(*crc, *value);
    return result;
}

int coco3_banked_bin_validate(coco3_banked_read_byte_fn read_byte,
                              void *context, uint32_t file_size,
                              struct coco3_banked_bin_info *info)
{
    static const uint8_t magic[4] = {'C','3','B','1'};
    uint8_t value, high, low;
    uint32_t offset = 0, payload_size = 0, expected_crc = 0;
    uint32_t crc = 0xffffffffu, payload_end;
    uint16_t old_address = 0;

    info->execution_descriptor = 0;
    info->payload_bytes = 0;
    info->data_records = 0;

    for (uint8_t n = 0; n < 4; ++n) {
        int result = file_byte(read_byte, context, file_size, &offset, &value);
        if (result)
            return result;
        if (value != magic[n])
            return COCO3_BANKED_BIN_NOT_FORMAT;
    }
    for (uint8_t n = 0; n < 4; ++n) {
        if (file_byte(read_byte, context, file_size, &offset, &value))
            return COCO3_BANKED_BIN_TRUNCATED;
        payload_size = (payload_size << 8) | value;
    }
    for (uint8_t n = 0; n < 4; ++n) {
        if (file_byte(read_byte, context, file_size, &offset, &value))
            return COCO3_BANKED_BIN_TRUNCATED;
        expected_crc = (expected_crc << 8) | value;
    }
    for (uint8_t n = 0; n < 4; ++n) {
        if (file_byte(read_byte, context, file_size, &offset, &value))
            return COCO3_BANKED_BIN_TRUNCATED;
        if (value)
            return COCO3_BANKED_BIN_BAD_HEADER;
    }
    if (!payload_size || payload_size > 0x20000u ||
        payload_size != file_size - COCO3_BANKED_BIN_HEADER_SIZE)
        return COCO3_BANKED_BIN_BAD_HEADER;
    payload_end = COCO3_BANKED_BIN_HEADER_SIZE + payload_size;

    for (;;) {
        uint16_t length, address, placement;
        uint32_t data_bytes;
        int result;

#define NEXT(v) do { \
    result = payload_byte(read_byte, context, file_size, payload_end, \
                          &offset, &crc, &(v)); \
    if (result) return result; \
} while (0)
        NEXT(value);
        if (value != 0)
            return COCO3_BANKED_BIN_BAD_RECORD;
        NEXT(high); NEXT(low);
        length = ((uint16_t)high << 8) | low;
        NEXT(high); NEXT(low);
        address = ((uint16_t)high << 8) | low;
        if (!length)
            return COCO3_BANKED_BIN_BAD_LENGTH;

        if (address != old_address) {
            if (length < 2)
                return COCO3_BANKED_BIN_BAD_LENGTH;
            NEXT(high); NEXT(low);
            placement = ((uint16_t)high << 8) | low;
            if (!placement) {
                if (length != 4 || !info->data_records)
                    return COCO3_BANKED_BIN_MISSING_DATA;
                NEXT(high); NEXT(low);
                info->execution_descriptor = ((uint16_t)high << 8) | low;
                if (offset != payload_end)
                    return COCO3_BANKED_BIN_BAD_LENGTH;
                if (~crc != expected_crc)
                    return COCO3_BANKED_BIN_BAD_CRC;
                info->payload_bytes = payload_size;
                return COCO3_BANKED_BIN_OK;
            }
            data_bytes = (uint32_t)length - 2u;
        } else {
            data_bytes = length;
        }

        if (data_bytes > payload_end - offset)
            return COCO3_BANKED_BIN_BAD_LENGTH;
        while (data_bytes--) NEXT(value);
        old_address = (uint16_t)(address + length);
        ++info->data_records;
#undef NEXT
    }
}
