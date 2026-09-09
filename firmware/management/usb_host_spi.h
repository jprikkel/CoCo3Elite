#ifndef COCO_USB_HOST_SPI_H
#define COCO_USB_HOST_SPI_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// A single foreground owner; do not call from an ISR concurrently.
typedef struct {
    volatile uint32_t *regs;
    uint32_t control;
} usb_host_spi;

bool usb_host_spi_init(usb_host_spi *spi, uintptr_t base);
bool usb_host_spi_select(usb_host_spi *spi, bool active);
bool usb_host_spi_transfer(usb_host_spi *spi, const uint8_t *tx, uint8_t *rx,
                           size_t length);
void usb_host_spi_abort(usb_host_spi *spi);
bool usb_host_spi_irq_pending(const usb_host_spi *spi);
// Reset and register/oscillator probe only. Never turns USB VBUS on, never
// enumerates devices. On failure the adapter is held in reset, CS inactive.
bool max3421_probe(usb_host_spi *spi, uint8_t *revision);
#endif
