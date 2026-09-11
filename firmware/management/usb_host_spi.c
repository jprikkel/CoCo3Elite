#include "usb_host_spi.h"

enum { ID, STATUS, CONTROL, DIVIDER, DATA, TIME_US };
enum { BUSY = 1, DONE = 2, ERROR = 4, INT_PENDING = 8, POWER_FAULT = 16 };
enum { SELECT = 1, RESET_N = 2 };
#define ABORT UINT32_C(0x80000000)
#define ABI_ID UINT32_C(0x55425331)
#define BYTE_TIMEOUT_US UINT32_C(25000)

static uint32_t read_reg(const usb_host_spi *spi, unsigned reg) {
    uint32_t value = spi->regs[reg];
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    return value;
}

static void write_reg(usb_host_spi *spi, unsigned reg, uint32_t value) {
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    spi->regs[reg] = value;
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
}

void usb_host_spi_abort(usb_host_spi *spi) {
    write_reg(spi, CONTROL, ABORT);
    spi->control = 0;
}

bool usb_host_spi_init(usb_host_spi *spi, uintptr_t base) {
    spi->regs = (volatile uint32_t *)base;
    spi->control = 0;
    if (read_reg(spi, ID) != ABI_ID) return false;
    usb_host_spi_abort(spi);
    write_reg(spi, STATUS, DONE | ERROR | POWER_FAULT);
    write_reg(spi, DIVIDER, 25); // 1 MHz at the prototype's 50 MHz clock
    return !(read_reg(spi, STATUS) & ERROR);
}

bool usb_host_spi_select(usb_host_spi *spi, bool active) {
    if (read_reg(spi, STATUS) & (BUSY | ERROR | POWER_FAULT)) {
        usb_host_spi_abort(spi);
        return false;
    }
    spi->control = active ? spi->control | SELECT : spi->control & ~SELECT;
    write_reg(spi, CONTROL, spi->control);
    if (read_reg(spi, STATUS) & ERROR) {
        usb_host_spi_abort(spi);
        return false;
    }
    return true;
}

bool usb_host_spi_transfer(usb_host_spi *spi, const uint8_t *tx, uint8_t *rx,
                           size_t length) {
    if ((spi->control & (SELECT | RESET_N)) != (SELECT | RESET_N)) return false;
    for (size_t i = 0; i < length; ++i) {
        if (read_reg(spi, STATUS) & (BUSY | ERROR | POWER_FAULT)) goto failed;
        write_reg(spi, DATA, tx ? tx[i] : 0);
        uint32_t started = read_reg(spi, TIME_US);
        for (;;) {
            uint32_t status = read_reg(spi, STATUS);
            if (status & (ERROR | POWER_FAULT)) goto failed;
            if (!(status & BUSY) && (status & DONE)) break;
            if ((uint32_t)(read_reg(spi, TIME_US) - started) >= BYTE_TIMEOUT_US)
                goto failed;
        }
        uint8_t value = (uint8_t)read_reg(spi, DATA);
        if (rx) rx[i] = value;
    }
    return true;
failed:
    usb_host_spi_abort(spi);
    return false;
}

bool usb_host_spi_irq_pending(const usb_host_spi *spi) {
    return (read_reg(spi, STATUS) & (INT_PENDING | POWER_FAULT)) != 0;
}

static void delay_us(usb_host_spi *spi, uint32_t delay) {
    uint32_t started = read_reg(spi, TIME_US);
    while ((uint32_t)(read_reg(spi, TIME_US) - started) < delay) { }
}

static bool max_reg(usb_host_spi *spi, uint8_t command, uint8_t value,
                    uint8_t *result) {
    uint8_t tx[2] = {command, value}, rx[2];
    if (!usb_host_spi_select(spi, true)) return false;
    if (!usb_host_spi_transfer(spi, tx, rx, sizeof(tx))) return false;
    if (!usb_host_spi_select(spi, false)) return false;
    if (result) *result = rx[1];
    return true;
}

bool max3421_probe(usb_host_spi *spi, uint8_t *revision) {
    uint8_t version = 0, pinctl = 0, usb_irq = 0;
    if (revision) *revision = 0;
    usb_host_spi_abort(spi);
    write_reg(spi, STATUS, DONE | ERROR | POWER_FAULT);
    delay_us(spi, 2000);
    spi->control = RESET_N;
    write_reg(spi, CONTROL, spi->control);
    delay_us(spi, 2000);
    // Encoded register address (register number << 3), write flag bit 1.
    // PINCTL: full-duplex SPI, active-low level interrupt.
    if (!max_reg(spi, 0x8a, 0x18, NULL)) goto failed;
    if (!max_reg(spi, 0x88, 0, &pinctl) || pinctl != 0x18) goto failed;
    if (!max_reg(spi, 0x90, 0, &version) || version == 0 || version == 0xff)
        goto failed;
    uint32_t started = read_reg(spi, TIME_US);
    do {
        if (!max_reg(spi, 0x68, 0, &usb_irq)) goto failed;
        if ((uint32_t)(read_reg(spi, TIME_US) - started) >= 100000) goto failed;
    } while (!(usb_irq & 1)); // USBIRQ.OSCOKIRQ
    if (revision) *revision = version; // Log actual silicon revision; do not guess it.
    return true;
failed:
    usb_host_spi_abort(spi);
    return false;
}
