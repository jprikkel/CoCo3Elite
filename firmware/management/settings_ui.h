#ifndef COCO3ELITE_SETTINGS_UI_H
#define COCO3ELITE_SETTINGS_UI_H
#include <stdint.h>

/* Call from the manager's main loop when F12 opens settings. */
void settings_ui_run(void);

/* Hardware abstraction: replace these addresses with the final manager map. */
void settings_hw_read(uint8_t *values, uint16_t count);
void settings_hw_write(const uint8_t *values, uint16_t count);

#endif
