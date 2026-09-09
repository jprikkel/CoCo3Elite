#include "sd_spi.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); } } while (0)

typedef struct {
    bool selected, idle, v2, hc, app, crc_on, absent, bad_echo, bad_ocr;
    bool bad_csd, protected_card, corrupt_crc, no_token, reject_read;
    bool reject_write, stuck_busy, never_ready, bad_status, fail_io;
    uint32_t us, hz, startup_clocks, arg, written_lba;
    unsigned commands, writes, busy_left, fail_after, transferred;
    uint8_t cmd[6], queue[600], storage[512], incoming[514];
    size_t cmdpos, qpos, qlen, writepos;
    bool wait_write, receiving, have_storage;
} model;
static unsigned tests;
static uint16_t data_crc(const uint8_t *data, size_t length) {
    // Polynomial long division, separately expressed from the driver.
    uint32_t rem = 0;
    for (size_t j = 0; j < length; ++j) {
        for (unsigned bit = 0; bit < 8; ++bit) {
            unsigned feedback = ((rem >> 15) ^ (data[j] >> (7-bit))) & 1;
            rem = (rem << 1) & 0xffff;
            if (feedback) rem ^= 0x1021;
        }
    }
    return (uint16_t)rem;
}
static uint8_t cmd_crc(const uint8_t *p) {
    unsigned rem = 0;
    for (unsigned j = 0; j < 5; ++j)
        for (unsigned b = 0; b < 8; ++b) {
            unsigned feedback = ((rem >> 6) ^ (p[j] >> (7-b))) & 1;
            rem = (rem << 1) & 0x7f;
            if (feedback) rem ^= 9;
        }
    return (uint8_t)(rem * 2 + 1);
}
static void push(model *m, uint8_t v) { CHECK(m->qlen < sizeof(m->queue)); m->queue[m->qlen++] = v; }
static void block(model *m, const uint8_t *data, size_t length) {
    push(m, 0xff); push(m, 0xfe);
    for (size_t i = 0; i < length; ++i) push(m, data[i]);
    uint16_t crc = data_crc(data, length) ^ (m->corrupt_crc ? 1 : 0);
    push(m, (uint8_t)(crc >> 8)); push(m, (uint8_t)crc);
}
static uint8_t pattern(uint32_t lba, unsigned offset) { return (uint8_t)(lba * 13 + offset * 7 + (offset >> 8)); }
static void dispatch(model *m) {
    uint8_t cmd = m->cmd[0] & 63;
    m->commands++;
    CHECK(cmd_crc(m->cmd) == m->cmd[5]);
    m->arg = ((uint32_t)m->cmd[1] << 24) | ((uint32_t)m->cmd[2] << 16) |
             ((uint32_t)m->cmd[3] << 8) | m->cmd[4];
    m->qpos = m->qlen = 0;
    push(m, 0xff); // legal one-byte response delay
    switch (cmd) {
    case 0:
        CHECK(m->startup_clocks >= 80 && m->hz <= 400000 && m->cmd[5] == 0x95);
        m->idle = true; m->crc_on = false; m->app = false;
        push(m, 1); break;
    case 8:
        CHECK(m->arg == 0x1aa && m->cmd[5] == 0x87);
        push(m, m->v2 ? 1 : 5);
        if (m->v2) { push(m, 0); push(m, 0); push(m, 1); push(m, m->bad_echo ? 0xab : 0xaa); }
        break;
    case 55: m->app = true; push(m, m->idle ? 1 : 0); break;
    case 41:
        CHECK(m->app && m->arg == (m->v2 ? 0x40000000u : 0));
        m->app = false; m->idle = m->never_ready; push(m, m->idle ? 1 : 0); break;
    case 58:
        push(m, 0); push(m, (m->hc ? 0x40 : 0) | 0x80);
        push(m, m->bad_ocr ? 0 : 0xff); push(m, 0x80); push(m, 0); break;
    case 16: CHECK(!m->hc && m->arg == 512); push(m, 0); break;
    case 59: CHECK(m->arg == 1); m->crc_on = true; push(m, 0); break;
    case 9: {
        CHECK(m->crc_on);
        uint8_t csd[16] = {0};
        if (m->hc) { csd[0] = 0x40; csd[8] = 0x0f; csd[9] = 0xff; }
        else { csd[5] = 9; csd[7] = 0xff; csd[8] = 0xc0; csd[9] = 1; csd[10] = 0x80; }
        if (m->bad_csd) csd[0] = 0x80;
        if (m->protected_card) csd[14] = 0x20;
        push(m, 0); block(m, csd, 16); break;
    }
    case 17: {
        CHECK(!m->idle && m->crc_on);
        push(m, m->reject_read ? 0x20 : 0);
        if (m->no_token || m->reject_read) break;
        uint32_t lba = m->hc ? m->arg : m->arg / 512;
        if (!m->hc) CHECK(m->arg % 512 == 0);
        uint8_t data[512];
        for (unsigned i = 0; i < 512; ++i)
            data[i] = m->have_storage && lba == m->written_lba ? m->storage[i] : pattern(lba, i);
        block(m, data, 512); break;
    }
    case 24:
        CHECK(!m->idle && m->crc_on);
        push(m, 0); m->wait_write = true;
        m->written_lba = m->hc ? m->arg : m->arg / 512;
        if (!m->hc) CHECK(m->arg % 512 == 0);
        break;
    case 13:
        CHECK(m->busy_left == 0);
        push(m, 0); push(m, m->bad_status ? 0x20 : 0); break;
    default: CHECK(false);
    }
}
static bool select_card(void *ctx, bool active) {
    model *m = ctx;
    if (!active) {
        m->qpos = m->qlen = m->cmdpos = 0;
        m->wait_write = m->receiving = false;
    }
    m->selected = active;
    return true;
}
static bool frequency(void *ctx, uint32_t hz) { ((model *)ctx)->hz = hz; return true; }
static uint32_t clock_us(void *ctx) { model *m = ctx; m->us += 100; return m->us; }
static bool xfer(void *ctx, const uint8_t *tx, uint8_t *rx, size_t n) {
    model *m = ctx;
    for (size_t i = 0; i < n; ++i) {
        if (m->fail_io || (m->fail_after && ++m->transferred >= m->fail_after)) return false;
        m->us += 8000000 / m->hz + 1;
        uint8_t out = tx ? tx[i] : 0xff, in = 0xff;
        if (!m->selected) { CHECK(out == 0xff); m->startup_clocks += 8; }
        else if (m->absent) { }
        else if (m->qpos < m->qlen) { CHECK(out == 0xff); in = m->queue[m->qpos++]; }
        else if (m->busy_left) { in = 0; if (!m->stuck_busy) --m->busy_left; }
        else if (m->receiving) {
            m->incoming[m->writepos++] = out;
            if (m->writepos == sizeof(m->incoming)) {
                uint16_t crc = (uint16_t)m->incoming[512] << 8 | m->incoming[513];
                CHECK(crc == data_crc(m->incoming, 512));
                m->receiving = false; m->writes++;
                m->qpos = m->qlen = 0;
                push(m, m->reject_write ? 0x0b : 5);
                if (!m->reject_write) {
                    memcpy(m->storage, m->incoming, 512); m->have_storage = true;
                    m->busy_left = 10;
                }
            }
        } else if (m->wait_write) {
            if (out == 0xfe) { m->wait_write = false; m->receiving = true; m->writepos = 0; }
            else CHECK(out == 0xff);
        } else if (m->cmdpos || (out & 0xc0) == 0x40) {
            m->cmd[m->cmdpos++] = out;
            if (m->cmdpos == 6) { m->cmdpos = 0; dispatch(m); }
        } else CHECK(out == 0xff);
        if (rx) rx[i] = in;
    }
    return true;
}
static sd_spi_bus bus_for(model *m) {
    return (sd_spi_bus){m, select_card, xfer, frequency, clock_us};
}
static void reset_model(model *m) { *m = (model){.v2 = true, .hc = true}; }
static void init_ok(model *m, sd_spi_card *c) {
    CHECK(sd_spi_init_card(c, bus_for(m)) == SD_OK);
    CHECK(c->ready && !c->writes_enabled && !m->selected && m->hz == 3125000);
    CHECK(c->sector_count == (m->hc ? UINT64_C(4194304) : UINT64_C(32768)));
}
static void success_cases(bool v2, bool hc) {
    model m; sd_spi_card c; uint8_t data[512], saved[512];
    reset_model(&m); m.v2 = v2; m.hc = hc; init_ok(&m, &c);
    CHECK(sd_spi_read(&c, 7, data) == SD_OK);
    CHECK(m.arg == (hc ? 7u : 3584u));
    for (unsigned i = 0; i < 512; ++i) CHECK(data[i] == pattern(7, i));
    unsigned count = m.commands;
    CHECK(sd_spi_write(&c, 7, data) == SD_READ_ONLY && m.commands == count);
    CHECK(sd_spi_read(&c, (uint32_t)c.sector_count, data) == SD_RANGE && c.ready);
    CHECK(sd_spi_read(&c, UINT32_MAX, data) == SD_RANGE);
    CHECK(sd_spi_read(&c, 0, NULL) == SD_RANGE);
    for (unsigned i = 0; i < 512; ++i) saved[i] = (uint8_t)(i ^ (i >> 8) ^ 0xa5);
    c.writes_enabled = true;
    CHECK(sd_spi_write(&c, 7, saved) == SD_OK && m.writes == 1 && !m.selected);
    CHECK(sd_spi_read(&c, 7, data) == SD_OK && memcmp(data, saved, 512) == 0);
    CHECK(sd_spi_read(&c, 8, data) == SD_OK && data[0] == pattern(8, 0));
    CHECK(sd_spi_sync(&c) == SD_OK);
    // A re-initialization must recover a card already in SPI mode, and lock writes.
    init_ok(&m, &c);
    ++tests;
}
int main(void) {
    CHECK(data_crc((const uint8_t *)"123456789", 9) == 0x31c3);
    success_cases(true, true); success_cases(true, false); success_cases(false, false);
    model m; sd_spi_card c; uint8_t data[512] = {0};
    for (unsigned which = 0; which < 7; ++which) {
        reset_model(&m);
        switch (which) {
        case 0: m.absent = true; break;
        case 1: m.bad_echo = true; break;
        case 2: m.bad_ocr = true; break;
        case 3: m.bad_csd = true; break;
        case 4: m.corrupt_crc = true; break;
        case 5: m.never_ready = true; break;
        default: m.fail_io = true; break;
        }
        sd_result expected[] = {SD_TIMEOUT, SD_UNSUPPORTED, SD_UNSUPPORTED, SD_UNSUPPORTED,
                                SD_CRC, SD_TIMEOUT, SD_IO};
        CHECK(sd_spi_init_card(&c, bus_for(&m)) == expected[which]);
        CHECK(!c.ready && !c.writes_enabled && !m.selected); ++tests;
    }
    for (unsigned which = 0; which < 5; ++which) {
        reset_model(&m); init_ok(&m, &c);
        switch (which) {
        case 0: m.corrupt_crc = true; break;
        case 1: m.no_token = true; break;
        case 2: m.reject_read = true; break;
        case 3: m.absent = true; break;
        default: m.fail_after = 100; break; // removal during payload
        }
        sd_result expected[] = {SD_CRC, SD_TIMEOUT, SD_RESPONSE, SD_TIMEOUT, SD_IO};
        CHECK(sd_spi_read(&c, 7, data) == expected[which]);
        CHECK(!c.ready && !m.selected && sd_spi_read(&c, 7, data) == SD_NOT_READY); ++tests;
    }
    for (unsigned which = 0; which < 4; ++which) {
        reset_model(&m); init_ok(&m, &c); c.writes_enabled = true;
        switch (which) {
        case 0: m.reject_write = true; break;
        case 1: m.stuck_busy = true; break;
        case 2: m.bad_status = true; break;
        default: m.fail_after = 100; break;
        }
        sd_result expected[] = {SD_WRITE_REJECTED, SD_TIMEOUT, SD_CARD_STATUS, SD_IO};
        CHECK(sd_spi_write(&c, 7, data) == expected[which]);
        CHECK(!c.ready && !c.writes_enabled && !m.selected); ++tests;
    }
    reset_model(&m); m.protected_card = true; init_ok(&m, &c); c.writes_enabled = true;
    CHECK(sd_spi_write(&c, 7, data) == SD_READ_ONLY && m.writes == 0); ++tests;
    reset_model(&m); m.us = UINT32_MAX - 500; init_ok(&m, &c);
    m.us = UINT32_MAX - 1000; m.no_token = true;
    CHECK(sd_spi_read(&c, 7, data) == SD_TIMEOUT && !m.selected); ++tests;
    printf("PASS: sd_spi_test (%u scenarios, no physical media accessed)\n", tests);
    return 0;
}
