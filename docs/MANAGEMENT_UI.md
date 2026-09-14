# CoCo 3 Elite management UI

This document defines the visual direction, interaction model, and implementation plan for the FPGA management interface. The management processor owns the UI and opens it over the running CoCo display with **F12**.

The images below are design references. They define the intended layout and style; they are not screenshots of the current implementation.

## Visual references

### Disk and file browser

![CoCo 3 Elite disk browser concept](images/management-ui-disk-browser-concept.png)

### Settings

![CoCo 3 Elite settings concept](images/management-ui-settings-concept.png)

### Logo wordmark

![CoCo 3 RGB Elite logo concept](images/coco3-elite-logo-concept.png)

## Current implementation

The current firmware provides a functional 72-column by 28-row character overlay. The first visual refresh implements the mockup's framed layout, light gold-on-black palette, solid amber reverse-video file selection, split file/detail panes, graphical directory, disk, cartridge, and BIN icons, a dedicated Spleen 8x16 management font, and custom glyphs for a three-pixel rounded outer frame and continuous panel lines. Fixed labels use sentence case for easier reading. The browser header uses the `CoCo 3 /// Elite` wordmark with dedicated three-pixel red, green, and blue slash glyphs. The corner arcs join directly to the side and top/bottom strokes, while interior horizontal separators stop five pixels before the outer frame instead of forming hard T-junctions. It can:

- open and close with F12;
- browse FAT32 directories, including parent-directory navigation and long filenames;
- mount a `.DSK` image as drive 0;
- cold-start compatible `.CCC` cartridge images;
- validate, load, and execute DECB `.BIN` files;
- report SD-card, mount, and load failures;
- detect SD removal and reinsertions without writing a stale disk cache.

The current browser is implemented in `firmware/management/rv32_sd_mount.c`, with its palette and icon glyphs in `rtl/management/manager_osd.v`. The dedicated UI font is stored in `rtl/management/manager_font.mem`; its license and attribution are under `rtl/management/fonts`. A settings-screen prototype exists in `firmware/management/settings_ui.c`, but it is not yet integrated into the main F12 workflow.

## Target visual language

The UI should look like a polished extension of the CoCo rather than a modern desktop window:

- black or very dark translucent background;
- warm amber text, borders, and icons;
- solid amber/gold selection bar with black reverse-video text;
- fixed-width, pixel-oriented character shapes;
- thin double-line outer border and single-line panel dividers;
- restrained animation and no effects that interfere with video timing;
- consistent spacing and alignment across every screen.

The mockups use a 4:3 frame with generous safe margins. The compositor must center the overlay from the active video area rather than from raw HDMI timing totals. This avoids the offset and clipping problems seen in early OSD builds.

## Common screen structure

Every management screen should use the same shell:

1. A header containing `COCO 3 ELITE` and the current screen title.
2. A context area for the selected drive, path, category, or device.
3. A primary content area divided into panes when useful.
4. A status line for progress, validation, and errors.
5. A footer showing only the controls valid on the current screen.

Long operations should immediately display a clear status such as `READING DIRECTORY`, `MOUNTING DRIVE 0`, or `LOADING CARTRIDGE`. Errors should remain visible until acknowledged instead of closing the menu.

## Disk and file browser

The browser is the default F12 screen. Its target layout has a file list on the left and details for the selected entry on the right.

### Header and context

- Display the selected target drive.
- Display the complete current FAT32 path.
- Truncate long paths in the middle when necessary so the final directory remains visible.
- Show media-offline status in the same location when no SD card is present.

### File list

Use distinct icons or textual markers for:

- parent directory;
- directory;
- `.DSK` disk image;
- `.CCC` cartridge image;
- `.BIN` DECB executable;
- future `.BAS` program support;
- unsupported files, which should normally be hidden unless an option enables them.

The mounted image should have a persistent marker independent of the selection bar. Long filenames should be preserved in firmware and clipped only while drawing. Scrolling should keep the selection visible and should not rescan the directory on every key press.

### Detail pane

For the selected item, show information that is already known without delaying navigation:

- file size;
- file type and intended action;
- mounted drive, if applicable;
- read-only or write-protected state;
- validation state or CRC32 when calculated;
- compatibility notes for unsupported cartridge mappers or BIN layouts.

CRC calculation should be performed while loading or on explicit request, not every time the highlight moves.

### Browser controls

- **Up/Down:** move through entries.
- **Enter:** open a directory, mount a disk, or launch a supported file.
- **Space:** select the destination drive or open a small drive-assignment action, once multi-drive mounting is implemented.
- **Esc/F12:** close the UI and return to the CoCo.

Potentially destructive actions, such as discarding dirty cached sectors or replacing a mounted writable disk, must require confirmation or a successful flush first.

## Settings screen

The settings screen uses a category list on the left and editable options on the right. The initial categories are:

- Audio
- Video
- Joystick
- Cassette
- Floppy
- Cartridge
- Serial
- Ethernet

The first Audio page in the mockup contains volume, disk sounds, tape playthrough, and future audio-chip selection. Other categories should expose only settings backed by working firmware or RTL. Planned settings may be displayed as disabled, but must not appear operational.

### Settings controls

- **Left/Right:** change category.
- **Up/Down:** change option.
- **Enter:** edit, toggle, or confirm the selected value.
- **Esc:** cancel the current edit or return to the browser.
- **F12:** close the management UI.

Values should be staged while editing. Persistent settings require an explicit Apply operation after nonvolatile storage is available; Cancel restores the values present when the screen opened.

### Quick actions

The lower panel reserves shortcuts for:

- soft power or pause;
- hard CoCo reset;
- management-system reboot.

Quick actions are commands, not persistent settings. Hard reset and reboot should require confirmation. Resetting the CoCo must leave the management processor, mounted-disk metadata, and SD service in a defined state.

## SD-card behavior

- F12 must remain available before an SD card is initialized and when no card is inserted.
- Removing the card marks the media offline immediately and prevents dirty cache writeback.
- A mounted disk becomes unavailable after removal; it must not silently continue as writable media.
- Reinserting a card remounts FAT32 and refreshes the directory listing.
- A previously mounted file may be restored only after its identity and allocation are verified.
- The UI must clearly distinguish `NO SD CARD`, `READING CARD`, `READY`, and `MEDIA CHANGED`.

## Technical work required

The disk browser now uses 72 by 28 character cells, providing a wider 576-pixel browser with small horizontal and vertical margins and 17 visible file entries. The remaining implementation should be staged:

1. Refactor browser drawing into reusable screen, pane, list, status, and footer helpers.
2. Integrate browser and settings navigation under one F12 state machine.
3. Add a stable OSD geometry interface so firmware reads the supported columns and rows instead of compiling different assumptions.
4. Align the settings screen with the current 72 by 28 browser geometry.
5. Add per-cell foreground/background attributes or a small style table for amber text and teal selection.
6. Add a custom character ROM containing the final font, border pieces, arrows, folders, disks, cartridges, and executable icons.
7. Center and scale the overlay from the active video dimensions.
8. Add settings MMIO only for options with defined hardware behavior.
9. Add persistence after the settings format and storage location are versioned.

The file service, FAT32 parser, disk cache, and cartridge/BIN loaders should remain firmware responsibilities. HDL should provide deterministic primitives: character/attribute RAM, keyboard events, settings registers, reset controls, and storage/cache interfaces.

## Acceptance criteria

- F12 opens and closes reliably at boot, without an SD card, and while CoCo software is running.
- The overlay is centered, fully visible, and stable in every supported video mode.
- The browser navigates subdirectories and displays long filenames without corruption.
- Selection, mounted-file, disabled, warning, and error states are visually distinct.
- Disk mounting, cartridge launching, and BIN execution retain their current behavior.
- SD removal never triggers stale writeback; reinsertion produces a fresh directory scan.
- Settings do not alter hardware until the user commits an edit.
- The UI remains responsive while the CoCo is reset or paused.
- Automated tests cover navigation, clipping, scrolling, media changes, and MMIO state transitions.

## Scope note

These mockups are the target design language, not a requirement to reproduce glow, texture, or photographic effects in FPGA logic. The first hardware implementation should prioritize exact alignment, readable typography, consistent colors, and reliable interaction. Optional visual effects can be evaluated after timing and memory usage are known.
