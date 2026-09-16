#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "coco3_banked_bin_format.h"

struct reader { const uint8_t *bytes; uint32_t size, offset; };

static int read_byte(void *context, uint8_t *value)
{
    struct reader *reader = context;
    if (reader->offset >= reader->size) return 1;
    *value = reader->bytes[reader->offset++];
    return 0;
}

static uint32_t crc32_byte(uint32_t crc, uint8_t value)
{
    crc ^= value;
    for (uint8_t bit = 0; bit < 8; ++bit)
        crc = (crc >> 1) ^ ((crc & 1u) ? 0xedb88320u : 0u);
    return crc;
}

static void be32(uint8_t *bytes, uint32_t value)
{
    bytes[0] = (uint8_t)(value >> 24);
    bytes[1] = (uint8_t)(value >> 16);
    bytes[2] = (uint8_t)(value >> 8);
    bytes[3] = (uint8_t)value;
}

static int validate_bytes(const uint8_t *bytes, uint32_t size,
                          struct coco3_banked_bin_info *info)
{
    struct reader reader = {bytes, size, 0};
    return coco3_banked_bin_validate(read_byte, &reader, size, info);
}

static int validate_file(const char *path)
{
    FILE *file = fopen(path, "rb");
    long size;
    uint8_t *bytes;
    struct coco3_banked_bin_info info;
    int result;
    if (!file) { perror(path); return 1; }
    fseek(file, 0, SEEK_END); size = ftell(file); rewind(file);
    bytes = malloc((size_t)size);
    if (!bytes || fread(bytes, 1, (size_t)size, file) != (size_t)size) {
        fclose(file); return 1;
    }
    fclose(file);
    result = validate_bytes(bytes, (uint32_t)size, &info);
    free(bytes);
    if (result) {
        fprintf(stderr, "FAIL converted file validation: %d\n", result);
        return 1;
    }
    printf("PASS converted C3B1 file: %u records, %u payload bytes, entry %04X\n",
           info.data_records, (unsigned)info.payload_bytes,
           info.execution_descriptor);
    return 0;
}

int main(int argc, char **argv)
{
    static const uint8_t payload[] = {
        0x00,0x00,0x09,0x04,0x00,0x76,0x08,
        0x86,0xa5,0xb7,0xff,0x70,0x20,0xfe,
        0x00,0x00,0x04,0x00,0x00,0x00,0x00,0x76,0x08
    };
    uint8_t image[COCO3_BANKED_BIN_HEADER_SIZE + sizeof payload] = {0};
    struct coco3_banked_bin_info info;
    uint32_t crc = 0xffffffffu;
    int result;

    memcpy(image, "C3B1", 4);
    be32(image + 4, sizeof payload);
    for (unsigned n = 0; n < sizeof payload; ++n)
        crc = crc32_byte(crc, payload[n]);
    be32(image + 8, ~crc);
    memcpy(image + COCO3_BANKED_BIN_HEADER_SIZE, payload, sizeof payload);

    result = validate_bytes(image, sizeof image, &info);
    if (result || info.data_records != 1 || info.payload_bytes != sizeof payload ||
        info.execution_descriptor != 0x7608u) {
        fprintf(stderr, "FAIL valid C3B1 image: %d\n", result); return 1;
    }
    image[0] = 'X';
    if (validate_bytes(image, sizeof image, &info) != COCO3_BANKED_BIN_NOT_FORMAT) {
        fprintf(stderr, "FAIL non-C3B1 image accepted\n"); return 1;
    }
    image[0] = 'C'; image[8] ^= 1;
    if (validate_bytes(image, sizeof image, &info) != COCO3_BANKED_BIN_BAD_CRC) {
        fprintf(stderr, "FAIL bad CRC accepted\n"); return 1;
    }
    image[8] ^= 1;
    if (validate_bytes(image, sizeof image - 1u, &info) != COCO3_BANKED_BIN_BAD_HEADER) {
        fprintf(stderr, "FAIL truncated payload accepted\n"); return 1;
    }
    image[12] = 1;
    if (validate_bytes(image, sizeof image, &info) != COCO3_BANKED_BIN_BAD_HEADER) {
        fprintf(stderr, "FAIL reserved header accepted\n"); return 1;
    }
    puts("PASS generic C3B1 banked BIN validation");
    return argc == 2 ? validate_file(argv[1]) : 0;
}
