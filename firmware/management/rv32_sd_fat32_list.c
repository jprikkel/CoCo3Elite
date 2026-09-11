#include <stdint.h>

// Standalone, read-only FAT32 bring-up firmware.  This intentionally contains
// only enough filesystem code to prove the manager CPU and the block-device
// contract.  FatFs will replace this parser once the transport is qualified.
#define REG32(a) (*(volatile uint32_t *)(a))
#define UART_DATA   REG32(0x80000000u)
#define UART_STATUS REG32(0x80000004u)
#define SPI_CTRL    REG32(0x80000100u)
#define SPI_XFER    REG32(0x80000104u)
#define SPI_DATA    REG32(0x80000108u)

static uint8_t sector[512];
static uint8_t block_addressed;
static uint32_t volume_lba, fat_lba, first_data_lba;
static uint8_t sectors_per_cluster;

static void putc(char c) {
    while (UART_STATUS & 1u) { }
    UART_DATA = (uint8_t)c;
}
static void puts(const char *s) { while (*s) putc(*s++); }
static void hex(uint8_t value) {
    static const char digits[] = "0123456789ABCDEF";
    putc(digits[value >> 4]); putc(digits[value & 15]);
}
static uint8_t xfer(uint8_t value) {
    SPI_XFER = value;                 // hardware ACK is delayed until complete
    return (uint8_t)SPI_DATA;
}
static void deselect(void) { SPI_CTRL = 0x00004001u; (void)xfer(0xff); }
static void select(void) { SPI_CTRL = 0x00004000u; }
static uint8_t ready(void) {
    for (uint32_t n = 0; n != 100000u; ++n)
        if (xfer(0xff) == 0xff) return 1;
    return 0;
}
static uint8_t command(uint8_t cmd, uint32_t arg) {
    deselect(); select();
    if (cmd != 0 && !ready()) return 0xff;
    (void)xfer((uint8_t)(0x40u | cmd));
    (void)xfer((uint8_t)(arg >> 24));
    (void)xfer((uint8_t)(arg >> 16));
    (void)xfer((uint8_t)(arg >> 8));
    (void)xfer((uint8_t)arg);
    (void)xfer(cmd == 0 ? 0x95 : (cmd == 8 ? 0x87 : 0x01));
    for (uint8_t n = 0; n != 16; ++n) {
        uint8_t r1 = xfer(0xff);
        if (!(r1 & 0x80)) return r1;
    }
    return 0xff;
}
static int init_card(void) {
    SPI_CTRL = 0x00004001u;           // CS high, 50 MHz/(2*64) startup clock
    for (uint8_t n = 0; n != 10; ++n) (void)xfer(0xff);
    for (uint8_t n = 0; n != 32; ++n) {
        if (command(0, 0) == 1) break;
        if (n == 31) return 1;
    }
    if (command(8, 0x1aau) != 1) return 2;
    if (xfer(0xff) || xfer(0xff) || xfer(0xff) != 1 || xfer(0xff) != 0xaa) return 3;
    for (uint16_t n = 0; n != 2000; ++n) {
        if (command(55, 0) > 1) return 4;
        if (command(41, 0x40000000u) == 0) break;
        if (n == 1999) return 5;
    }
    if (command(58, 0) != 0) return 6;
    uint8_t ocr0 = xfer(0xff);
    (void)xfer(0xff); (void)xfer(0xff); (void)xfer(0xff);
    deselect();
    if (!(ocr0 & 0x80u)) return 7;
    block_addressed = (ocr0 & 0x40u) != 0;
    // SDSC cards use byte addresses and require an explicit 512-byte block
    // length.  SDHC/SDXC cards use logical block addresses and reject CMD16.
    if (!block_addressed && command(16, 512) != 0) return 8;
    deselect();
    SPI_CTRL = 0x00000801u;           // CS high, 3.125 MHz transfer clock
    return 0;
}
static int read_sector(uint32_t lba) {
    if (!block_addressed && lba > 0x007fffffu) return 4;
    if (command(17, block_addressed ? lba : lba * 512u) != 0) { deselect(); return 1; }
    for (uint32_t n = 0; n != 100000u; ++n) {
        uint8_t token = xfer(0xff);
        if (token == 0xfe) goto data;
        if (token != 0xff) { deselect(); return 2; }
    }
    deselect(); return 3;
data:
    for (uint16_t n = 0; n != 512; ++n) sector[n] = xfer(0xff);
    (void)xfer(0xff); (void)xfer(0xff); // CRC is disabled until the FatFs stage.
    deselect();
    return 0;
}
static uint16_t le16(const uint8_t *p) { return (uint16_t)p[0] | ((uint16_t)p[1] << 8); }
static uint32_t le32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static void filename(const uint8_t *entry) {
    int end = 7;
    while (end >= 0 && entry[end] == ' ') --end;
    for (int n = 0; n <= end; ++n) putc((char)entry[n]);
    end = 10;
    while (end >= 8 && entry[end] == ' ') --end;
    if (end >= 8) {
        putc('.');
        for (int n = 8; n <= end; ++n) putc((char)entry[n]);
    }
    puts("\r\n");
}
static int is_readme(const uint8_t *entry) {
    static const char name[11] = {'R','E','A','D','M','E',' ',' ','T','X','T'};
    for (uint8_t n = 0; n != 11; ++n) if (entry[n] != (uint8_t)name[n]) return 0;
    return 1;
}
static int next_cluster(uint32_t cluster, uint32_t *next) {
    if (read_sector(fat_lba + (cluster >> 7))) return 1;
    *next = le32(&sector[(cluster & 127u) * 4u]) & 0x0fffffffu;
    return *next >= 0x0ffffff8u || *next < 2u;
}
static int file_byte(uint32_t cluster, uint32_t offset, uint8_t *value) {
    uint32_t cluster_bytes = (uint32_t)sectors_per_cluster * 512u;
    while (offset >= cluster_bytes) {
        offset -= cluster_bytes;
        if (next_cluster(cluster, &cluster)) return 1;
    }
    if (read_sector(first_data_lba + (cluster - 2u) * sectors_per_cluster + (offset >> 9))) return 1;
    *value = sector[offset & 511u];
    return 0;
}
static int list_root(void) {
    if (read_sector(0)) return 0x10;
    if (sector[510] != 0x55 || sector[511] != 0xaa) return 0x11;
    if (sector[82] == 'F' && sector[83] == 'A' && sector[84] == 'T' && sector[85] == '3' && sector[86] == '2')
        volume_lba = 0;
    else volume_lba = le32(&sector[454]);
    if (!volume_lba && !(sector[82] == 'F' && sector[83] == 'A')) return 0x12;
    if (read_sector(volume_lba)) return 0x13;
    if (sector[510] != 0x55 || sector[511] != 0xaa || le16(&sector[11]) != 512) return 0x14;
    sectors_per_cluster = sector[13];
    uint16_t reserved = le16(&sector[14]);
    uint8_t fats = sector[16];
    uint32_t fat_sectors = le32(&sector[36]);
    uint32_t root_cluster = le32(&sector[44]);
    if (!sectors_per_cluster || !fats || root_cluster < 2 || !fat_sectors) return 0x15;
    fat_lba = volume_lba + reserved;
    first_data_lba = fat_lba + (uint32_t)fats * fat_sectors;
    uint32_t root_lba = first_data_lba + (root_cluster - 2u) * sectors_per_cluster;
    uint32_t readme_cluster = 0, readme_size = 0;
    puts("FAT32 ROOT\r\n");
    for (uint8_t s = 0; s != sectors_per_cluster; ++s) {
        if (read_sector(root_lba + s)) return 0x16;
        for (uint16_t offset = 0; offset != 512; offset += 32) {
            const uint8_t *entry = &sector[offset];
            if (!entry[0]) goto root_done;
            if (entry[0] != 0xe5 && entry[11] != 0x0f && !(entry[11] & 0x18)) {
                filename(entry);
                if (is_readme(entry)) {
                    readme_cluster = ((uint32_t)le16(&entry[20]) << 16) | le16(&entry[26]);
                    readme_size = le32(&entry[28]);
                }
            }
        }
    }
root_done:
    if (readme_cluster < 2 || readme_size < 2) return 0x17;

    /* Show the literal final bytes, then disregard ordinary text-file EOLs. */
    puts("README RAW TAIL: ");
    uint32_t raw_start = readme_size > 4u ? readme_size - 4u : 0;
    for (uint32_t offset = raw_start; offset < readme_size; ++offset) {
        uint8_t value;
        if (file_byte(readme_cluster, offset, &value)) return 0x18;
        hex(value); putc(' ');
    }
    puts("\r\n");

    uint32_t text_end = readme_size;
    uint8_t last;
    while (text_end) {
        if (file_byte(readme_cluster, text_end - 1u, &last)) return 0x18;
        if (last != '\r' && last != '\n') break;
        --text_end;
    }
    if (text_end < 2u) return 0x19;
    uint8_t penultimate;
    if (file_byte(readme_cluster, text_end - 2u, &penultimate)) return 0x18;
    puts("README TEXT END: "); putc((char)penultimate); putc((char)last); puts("\r\n");
    return (penultimate == '4' && last == '2') ? 0 : 0x19;
}
int main(void) {
    puts("RV32 SD\r\n");
    int error = init_card();
    if (!error) error = list_root();
    if (error) { puts("ERR "); hex((uint8_t)error); puts("\r\n"); }
    else puts("END\r\n");
    for (;;) { }
}
