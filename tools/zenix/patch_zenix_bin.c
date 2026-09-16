#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ZENIX_FILE_SIZE 69119u
#define ZENIX_ENCRYPTED_OFFSET 2304u
#define ZENIX_PROGRAM_BYTES 59999u
#define C3B_HEADER_SIZE 16u

static uint32_t crc32_byte(uint32_t crc, uint8_t value)
{
    crc ^= value;
    for (uint8_t bit = 0; bit < 8; ++bit)
        crc = (crc >> 1) ^ ((crc & 1u) ? 0xedb88320u : 0u);
    return crc;
}

static uint16_t cipher_step(uint16_t state)
{
    uint8_t high = (uint8_t)(state >> 8), low = (uint8_t)state;
    uint16_t product = (uint16_t)low * 0x55u;
    uint8_t product_high = (uint8_t)(product >> 8);
    product_high = (uint8_t)(product_high +
                             (uint8_t)((uint16_t)low * 0x62u));
    product_high = (uint8_t)(product_high +
                             (uint8_t)((uint16_t)high * 0x55u));
    product = ((uint16_t)product_high << 8) | (uint8_t)product;
    return (uint16_t)(product + 0x3619u);
}

static int valid_source(const uint8_t *source, size_t size)
{
    static const struct { uint8_t offset, value; } signature[] = {
        {0x00,0x00},{0x01,0x00},{0x02,0x04},{0x03,0x30},{0x04,0x00},
        {0x05,0x27},{0x06,0x11},{0x07,0x03},{0x08,0xe9},
        {0x09,0x00},{0x0a,0x00},{0x0b,0x03},{0x0c,0x00},{0x0d,0x9f},
        {0x0e,0x7e},{0x0f,0xb2},{0x10,0x77},
        {0x1e,0x00},{0x1f,0x00},{0x20,0x24},{0x21,0x40},{0x22,0x00},
        {0x23,'Z'},{0x24,'E'},{0x25,'N'},{0x26,'I'},{0x27,'X'},
        {0x80,0xff},{0x81,0x00},{0x82,0x03},{0x83,0x0e},{0x84,0x00}
    };
    if (size != ZENIX_FILE_SIZE)
        return 0;
    for (size_t n = 0; n < sizeof signature / sizeof signature[0]; ++n)
        if (source[signature[n].offset] != signature[n].value)
            return 0;
    return 1;
}

static uint8_t patch_byte(uint32_t offset, uint8_t value)
{
    switch (offset) {
    case 0x22b1u: return 0x20u; /* accept patched program CRC */
    case 0x22bfu: case 0x22c0u: return 0x12u;

    /* Remove physical-disk initialization and score-file reads/writes. */
    case 0x22ecu: case 0x22edu: case 0x22eeu:
    case 0x22efu: case 0x22f0u: case 0x22f1u:
    case 0x22ffu: case 0x2300u: case 0x2301u:
    case 0x2325u: case 0x2326u: case 0x2327u:
    case 0x2421u: case 0x2422u: case 0x2423u:
        return 0x12u;

    /* DISKDEINIT normally restores double-speed mode after disk access. */
    case 0x2446u: case 0x2465u: return 0x7fu; /* CLR $FFD9 */
    case 0x2447u: case 0x2466u: return 0xffu;
    case 0x2448u: case 0x2467u: return 0xd9u;

    /* Replace the disk copy check with its accepted disk number. */
    case 0x2427u: return 0xccu;
    case 0x2428u: return 0x00u;
    case 0x2429u: return 0x01u;

    /* Reproduce the successful copy check's self-modifying menu unlock. */
    case 0x25b7u: case 0x25c5u: return 0xbdu; /* JSR BUTTON */
    case 0x25b8u: case 0x25c6u: return 0xdbu;
    case 0x25b9u: case 0x25c7u: return 0xfeu;
    case 0x2701u: case 0x2702u: return 0x12u; /* remove early return */
    case 0x2736u: return 0xe0u;               /* game entry $E000 */
    case 0x2737u: return 0x00u;
    default: return value;
    }
}

static int write_be32(FILE *file, uint32_t value)
{
    uint8_t bytes[4] = {(uint8_t)(value >> 24), (uint8_t)(value >> 16),
                        (uint8_t)(value >> 8), (uint8_t)value};
    return fwrite(bytes, 1, sizeof bytes, file) == sizeof bytes ? 0 : 1;
}

int main(int argc, char **argv)
{
    uint8_t *source, *payload;
    FILE *file;
    long input_size;
    uint16_t state = 0x2711u;
    uint8_t chain = 0;
    uint32_t crc = 0xffffffffu;

    if (argc != 3) {
        fprintf(stderr, "usage: patch_zenix_bin INPUT OUTPUT\n");
        return 2;
    }
    if (!strcmp(argv[1], argv[2])) {
        fprintf(stderr, "input and output must be different files\n");
        return 2;
    }
    file = fopen(argv[1], "rb");
    if (!file) { perror("open input"); return 3; }
    if (fseek(file, 0, SEEK_END) || (input_size = ftell(file)) < 0 ||
        fseek(file, 0, SEEK_SET)) {
        fclose(file); return 3;
    }
    source = (uint8_t *)malloc((size_t)input_size);
    payload = (uint8_t *)malloc(ZENIX_PROGRAM_BYTES);
    if (!source || !payload) { fclose(file); return 4; }
    if (fread(source, 1, (size_t)input_size, file) != (size_t)input_size) {
        fclose(file); return 3;
    }
    fclose(file);
    if (!valid_source(source, (size_t)input_size)) {
        fprintf(stderr, "input is not the supported original ZENIX.BIN\n");
        return 5;
    }

    for (uint32_t n = 0; n < ZENIX_PROGRAM_BYTES; ++n) {
        if (!(n & 255u)) {
            state = cipher_step(state);
            chain = (uint8_t)(state >> 8);
        }
        payload[n] = source[ZENIX_ENCRYPTED_OFFSET + n] ^ chain;
        chain = payload[n];
        payload[n] = patch_byte(n, payload[n]);
        crc = crc32_byte(crc, payload[n]);
    }
    crc = ~crc;

    file = fopen(argv[2], "wb");
    if (!file) { perror("open output"); return 6; }
    if (fwrite("C3B1", 1, 4, file) != 4 ||
        write_be32(file, ZENIX_PROGRAM_BYTES) || write_be32(file, crc) ||
        write_be32(file, 0) ||
        fwrite(payload, 1, ZENIX_PROGRAM_BYTES, file) != ZENIX_PROGRAM_BYTES ||
        fclose(file)) {
        fprintf(stderr, "failed writing output\n");
        return 6;
    }
    printf("Wrote %s: C3B1 payload %u bytes, CRC32 %08X\n",
           argv[2], (unsigned)ZENIX_PROGRAM_BYTES, (unsigned)crc);
    free(payload);
    free(source);
    return 0;
}
