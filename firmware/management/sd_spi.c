#include "sd_spi.h"

#define READY_US UINT32_C(500000)
#define INIT_US UINT32_C(2000000)
#define READ_US UINT32_C(200000)

static uint16_t crc16(const uint8_t *p, size_t n) {
    uint16_t crc = 0;
    while (n--) {
        crc ^= (uint16_t)*p++ << 8;
        for (unsigned i = 0; i < 8; ++i)
            crc = (uint16_t)((crc << 1) ^ ((crc & 0x8000) ? 0x1021 : 0));
    }
    return crc;
}
static uint8_t command_crc(const uint8_t *p) {
    uint8_t crc = 0;
    for (unsigned n = 0; n < 5; ++n) {
        uint8_t v = p[n];
        for (unsigned i = 0; i < 8; ++i) {
            crc <<= 1;
            if ((v ^ crc) & 0x80) crc ^= 0x09;
            v <<= 1;
        }
    }
    return (uint8_t)((crc << 1) | 1);
}
static uint32_t now(sd_spi_card *c) { return c->bus.time_us(c->bus.ctx); }
static bool elapsed(sd_spi_card *c, uint32_t start, uint32_t limit) {
    return (uint32_t)(now(c) - start) >= limit;
}
static sd_result bytes(sd_spi_card *c, const uint8_t *tx, uint8_t *rx, size_t n) {
    return c->bus.transfer(c->bus.ctx, tx, rx, n) ? SD_OK : SD_IO;
}
static sd_result clock_byte(sd_spi_card *c, uint8_t *rx) {
    uint8_t tx = 0xff;
    return bytes(c, &tx, rx, 1);
}
static sd_result deselect(sd_spi_card *c) {
    if (!c->bus.select(c->bus.ctx, false)) return SD_IO;
    return clock_byte(c, NULL); // release MISO; also clocks when CS is high
}
static sd_result complete(sd_spi_card *c, sd_result result) {
    sd_result cleanup = deselect(c);
    if (result == SD_OK) result = cleanup;
    if (result != SD_OK) {
        c->ready = false;
        c->writes_enabled = false; // require re-init after uncertain I/O
    }
    return result;
}
static sd_result wait_ready(sd_spi_card *c) {
    uint32_t start = now(c);
    do {
        uint8_t value;
        sd_result r = clock_byte(c, &value);
        if (r != SD_OK) return r;
        if (value == 0xff) return SD_OK;
    } while (!elapsed(c, start, READY_US));
    return SD_TIMEOUT;
}
static sd_result command(sd_spi_card *c, uint8_t cmd, uint32_t arg) {
    sd_result r = deselect(c);
    if (r != SD_OK || !c->bus.select(c->bus.ctx, true)) return SD_IO;
    // CMD0 must be usable before the card has entered SPI mode.
    if (cmd != 0 && (r = wait_ready(c)) != SD_OK) return r;
    uint8_t packet[6] = {(uint8_t)(0x40 | cmd), (uint8_t)(arg >> 24),
        (uint8_t)(arg >> 16), (uint8_t)(arg >> 8), (uint8_t)arg, 0};
    packet[5] = command_crc(packet);
    r = bytes(c, packet, NULL, sizeof(packet));
    if (r != SD_OK) return r;
    for (unsigned i = 0; i < 8; ++i) {
        r = clock_byte(c, &c->last_r1);
        if (r != SD_OK) return r;
        if (!(c->last_r1 & 0x80)) return SD_OK;
    }
    return SD_TIMEOUT;
}
static sd_result command_ok(sd_spi_card *c, uint8_t cmd, uint32_t arg) {
    sd_result r = command(c, cmd, arg);
    return r != SD_OK ? r : (c->last_r1 == 0 ? SD_OK : SD_RESPONSE);
}
static sd_result receive(sd_spi_card *c, uint8_t *data, size_t n) {
    uint32_t start = now(c);
    do {
        sd_result r = clock_byte(c, &c->last_token);
        if (r != SD_OK) return r;
        if (c->last_token == 0xfe) {
            // A null TX buffer in this SD bus API means send 0xff, not zero.
            r = bytes(c, NULL, data, n);
            if (r != SD_OK) return r;
            uint8_t crc[2];
            r = bytes(c, NULL, crc, 2);
            if (r != SD_OK) return r;
            return crc16(data, n) == ((uint16_t)crc[0] << 8 | crc[1]) ? SD_OK : SD_CRC;
        }
        if (c->last_token != 0xff) return SD_RESPONSE;
    } while (!elapsed(c, start, READ_US));
    return SD_TIMEOUT;
}

sd_result sd_spi_init_card(sd_spi_card *c, sd_spi_bus bus) {
    *c = (sd_spi_card){.bus = bus, .last_r1 = 0xff, .last_token = 0xff};
    if (!bus.select || !bus.transfer || !bus.frequency || !bus.time_us) return SD_IO;
    if (!bus.frequency(bus.ctx, 400000)) return complete(c, SD_IO);
    if (!bus.select(bus.ctx, false)) return complete(c, SD_IO);
    uint32_t start = now(c);
    while (!elapsed(c, start, 2000)) { } // card supply settling, not a power switch
    for (unsigned i = 0; i < 10; ++i)
        if (clock_byte(c, NULL) != SD_OK) return complete(c, SD_IO);
    sd_result r = command(c, 0, 0);
    if (r != SD_OK || c->last_r1 != 1) return complete(c, r != SD_OK ? r : SD_RESPONSE);
    r = command(c, 8, 0x1aa);
    if (r != SD_OK) return complete(c, r);
    bool v2 = c->last_r1 == 1;
    if (v2) {
        uint8_t r7[4];
        if ((r = bytes(c, NULL, r7, 4)) != SD_OK) return complete(c, r);
        if (r7[0] || r7[1] || r7[2] != 1 || r7[3] != 0xaa)
            return complete(c, SD_UNSUPPORTED);
    } else if (c->last_r1 != 5) return complete(c, SD_UNSUPPORTED);

    start = now(c);
    do {
        if ((r = command(c, 55, 0)) != SD_OK) return complete(c, r);
        if (c->last_r1 > 1) return complete(c, SD_UNSUPPORTED); // no MMC fallback
        if ((r = command(c, 41, v2 ? UINT32_C(0x40000000) : 0)) != SD_OK)
            return complete(c, r);
        if (c->last_r1 == 0) break;
        if (c->last_r1 != 1) return complete(c, SD_RESPONSE);
        if (elapsed(c, start, INIT_US)) return complete(c, SD_TIMEOUT);
    } while (true);
    if ((r = command_ok(c, 58, 0)) != SD_OK) return complete(c, r);
    uint8_t ocr[4];
    if ((r = bytes(c, NULL, ocr, 4)) != SD_OK) return complete(c, r);
    if (!(ocr[0] & 0x80) || !(ocr[1] & 0x30) || (!v2 && (ocr[0] & 0x40)))
        return complete(c, SD_UNSUPPORTED);
    c->block_addressed = (ocr[0] & 0x40) != 0;
    if (!c->block_addressed && (r = command_ok(c, 16, 512)) != SD_OK)
        return complete(c, r);
    // Enable CRC checking on the card as well as checking read CRC locally.
    if ((r = command_ok(c, 59, 1)) != SD_OK) return complete(c, r);
    if ((r = command_ok(c, 9, 0)) != SD_OK) return complete(c, r);
    uint8_t csd[16];
    if ((r = receive(c, csd, sizeof(csd))) != SD_OK) return complete(c, r);
    if ((csd[0] >> 6) == 1 && c->block_addressed) {
        uint32_t size = ((uint32_t)(csd[7] & 0x3f) << 16) | ((uint32_t)csd[8] << 8) | csd[9];
        c->sector_count = ((uint64_t)size + 1) << 10;
    } else if ((csd[0] >> 6) == 0 && !c->block_addressed) {
        unsigned read_len = csd[5] & 15;
        unsigned mult = ((csd[9] & 3) << 1) | (csd[10] >> 7);
        uint32_t size = ((uint32_t)(csd[6] & 3) << 10) | ((uint32_t)csd[7] << 2) | (csd[8] >> 6);
        if (read_len < 9 || read_len > 11) return complete(c, SD_UNSUPPORTED);
        c->sector_count = ((uint64_t)size + 1) << (mult + 2 + read_len - 9);
        if (c->sector_count > (UINT64_C(1) << 23)) return complete(c, SD_UNSUPPORTED);
    } else return complete(c, SD_UNSUPPORTED);
    c->card_write_protected = (csd[14] & 0x30) != 0;
    if ((r = complete(c, SD_OK)) != SD_OK) return r;
    if (!bus.frequency(bus.ctx, 3125000)) return complete(c, SD_IO);
    c->ready = true;
    return SD_OK;
}

static sd_result check_address(sd_spi_card *c, uint32_t lba, uint32_t *address) {
    if (!c->ready) return SD_NOT_READY;
    if ((uint64_t)lba >= c->sector_count || (!c->block_addressed && lba > UINT32_MAX / 512))
        return SD_RANGE;
    *address = c->block_addressed ? lba : lba * 512;
    return SD_OK;
}
sd_result sd_spi_read(sd_spi_card *c, uint32_t lba, uint8_t data[512]) {
    uint32_t address;
    sd_result r = check_address(c, lba, &address);
    if (r != SD_OK) return r;
    if (!data) return SD_RANGE;
    r = command_ok(c, 17, address);
    if (r == SD_OK) r = receive(c, data, 512);
    // Caller must discard data on any error (it may be partial or CRC-invalid).
    return complete(c, r);
}
sd_result sd_spi_sync(sd_spi_card *c) {
    if (!c->ready) return SD_NOT_READY;
    sd_result r = command_ok(c, 13, 0); // waits for not-busy, then reads R2
    uint8_t r2 = 0xff;
    if (r == SD_OK) r = clock_byte(c, &r2);
    if (r == SD_OK && r2 != 0) r = SD_CARD_STATUS;
    return complete(c, r);
}
sd_result sd_spi_write(sd_spi_card *c, uint32_t lba, const uint8_t data[512]) {
    uint32_t address;
    sd_result r = check_address(c, lba, &address);
    if (r != SD_OK) return r;
    if (!c->writes_enabled || c->card_write_protected) return SD_READ_ONLY;
    if (!data) return SD_RANGE;
    r = command_ok(c, 24, address);
    if (r != SD_OK) return complete(c, r);
    uint8_t lead[2] = {0xff, 0xfe};
    uint16_t crc = crc16(data, 512);
    uint8_t tail[2] = {(uint8_t)(crc >> 8), (uint8_t)crc};
    if ((r = bytes(c, lead, NULL, 2)) == SD_OK) r = bytes(c, data, NULL, 512);
    if (r == SD_OK) r = bytes(c, tail, NULL, 2);
    if (r == SD_OK) r = clock_byte(c, &c->last_token);
    if (r == SD_OK && (c->last_token & 0x1f) != 5) r = SD_WRITE_REJECTED;
    if (r == SD_OK) r = wait_ready(c);
    if ((r = complete(c, r)) != SD_OK) return r;
    return sd_spi_sync(c); // never report success solely from data-accepted token
}
