#ifndef COCO_SD_SPI_H
#define COCO_SD_SPI_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Single foreground owner. Callbacks must return on transport failure; time_us
// must advance independently, including while the card is absent/busy.
typedef struct {
    void *ctx;
    bool (*select)(void *ctx, bool active);
    bool (*transfer)(void *ctx, const uint8_t *tx, uint8_t *rx, size_t length);
    bool (*frequency)(void *ctx, uint32_t maximum_hz);
    uint32_t (*time_us)(void *ctx);
} sd_spi_bus;
typedef enum {
    SD_OK, SD_NOT_READY, SD_IO, SD_TIMEOUT, SD_RESPONSE, SD_UNSUPPORTED,
    SD_CRC, SD_RANGE, SD_READ_ONLY, SD_WRITE_REJECTED, SD_CARD_STATUS
} sd_result;
typedef struct {
    sd_spi_bus bus;
    uint64_t sector_count;
    bool ready, block_addressed, card_write_protected, writes_enabled;
    uint8_t last_r1, last_token;
} sd_spi_card;

// Initializes SDSC(v1/v2)/SDHC/SDXC SPI cards. No MMC or SDUC. Always starts
// read-only; an upper layer must explicitly set writes_enabled after validation.
sd_result sd_spi_init_card(sd_spi_card *card, sd_spi_bus bus);
sd_result sd_spi_read(sd_spi_card *card, uint32_t lba, uint8_t data[512]);
sd_result sd_spi_write(sd_spi_card *card, uint32_t lba, const uint8_t data[512]);
sd_result sd_spi_sync(sd_spi_card *card);
#endif
