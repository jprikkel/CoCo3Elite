#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "decb_bin_format.h"

struct reader { const uint8_t *bytes; uint32_t size, offset; };
static int failures;

static int read_byte(void *context, uint8_t *value)
{
    struct reader *reader = context;
    if (reader->offset >= reader->size)
        return 1;
    *value = reader->bytes[reader->offset++];
    return 0;
}

static void expect(const char *name, const uint8_t *bytes, uint32_t size,
                   int wanted, uint16_t execution, uint32_t data_bytes,
                   uint32_t stream_bytes)
{
    struct reader reader = { bytes, size, 0 };
    struct decb_bin_info info;
    int actual = decb_bin_validate(read_byte, &reader, size, &info);
    if (actual != wanted ||
        (wanted == DECB_BIN_OK &&
         (info.execution_address != execution || info.data_bytes != data_bytes ||
          info.stream_bytes != stream_bytes))) {
        fprintf(stderr, "FAIL %s: result=%d exec=%04x bytes=%lu stream=%lu\n", name,
                actual, info.execution_address, (unsigned long)info.data_bytes,
                (unsigned long)info.stream_bytes);
        ++failures;
    } else {
        printf("PASS %s\n", name);
    }
}

int main(void)
{
    static const uint8_t one_record[] = {
        0x00,0x00,0x03,0x60,0x00,0x12,0x34,0x56,
        0xff,0x00,0x00,0x60,0x00
    };
    static const uint8_t two_records[] = {
        0x00,0x00,0x01,0x20,0x00,0xaa,
        0x00,0x00,0x02,0xc0,0x00,0xbb,0xcc,
        0xff,0x00,0x00,0x20,0x00
    };
    static const uint8_t truncated[] = {0x00,0x00,0x02,0x60,0x00,0xaa};
    static const uint8_t missing_exec[] = {0x00,0x00,0x01,0x60,0x00,0xaa};
    static const uint8_t io_overlap[] = {
        0x00,0x00,0x01,0xff,0x63,0xaa,
        0xff,0x00,0x00,0x60,0x00
    };
    static const uint8_t gime_write[] = {
        0x00,0x00,0x01,0xff,0xa2,0xaa,
        0xff,0x00,0x00,0x60,0x00
    };
    static const uint8_t loader_overlap[] = {
        0x00,0x00,0x01,0xfe,0x20,0xaa,
        0xff,0x00,0x00,0x60,0x00
    };
    static const uint8_t trailing[] = {
        0x00,0x00,0x01,0x60,0x00,0xaa,
        0xff,0x00,0x00,0x60,0x00,0x99
    };
    static const uint8_t raw[] = {0x12,0x34,0x56,0x78,0x9a};

    expect("one record", one_record, sizeof one_record, DECB_BIN_OK, 0x6000, 3, sizeof one_record);
    expect("multiple records", two_records, sizeof two_records, DECB_BIN_OK, 0x2000, 3, sizeof two_records);
    expect("truncated data", truncated, sizeof truncated, DECB_BIN_BAD_LENGTH, 0, 0, 0);
    expect("missing trailer", missing_exec, sizeof missing_exec, DECB_BIN_TRUNCATED, 0, 0, 0);
    expect("loader mailbox overlap", io_overlap, sizeof io_overlap, DECB_BIN_IO_OVERLAP, 0, 0, 0);
    expect("GIME register write", gime_write, sizeof gime_write, DECB_BIN_OK, 0x6000, 1, sizeof gime_write);
    expect("loader overlap", loader_overlap, sizeof loader_overlap, DECB_BIN_LOADER_OVERLAP, 0, 0, 0);
    expect("trailing granule padding", trailing, sizeof trailing, DECB_BIN_OK, 0x6000, 1, sizeof trailing - 1u);
    expect("raw binary", raw, sizeof raw, DECB_BIN_BAD_RECORD, 0, 0, 0);
    return failures != 0;
}
