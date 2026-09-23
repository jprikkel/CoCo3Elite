# Launching CoCo3Elite regression programs

This is the repeatable **COM5 / SD-card** launch checklist. Do not infer a pass
from a title screen or `DIR` alone: check the expected directory, load/run the
program, keep it running, and inspect the final video and CPU state. The most
useful 512K disk regressions are Joust and Pac-Man, not a low-resolution game
with the same name elsewhere on the card.

## Start from a known browser state

1. Close any PuTTY or other COM5 client. Only one process may own the port.
2. With the CoCo at BASIC, send `ROOT`, **then** press F12 to open the browser.
   `ROOT` changes the browser directory but does not open it. If F12 closes an
   already-open browser, press F12 again. Confirm the displayed path is `/`.
3. The browser selects its first entry on entering a directory; that entry is
   `..` in subdirectories. Pulse each key (press, wait at least 140 ms,
   release, wait at least 180 ms). Do not send a burst of key-down messages.
4. Use the displayed path and filename as the authority. The counts below
   describe the current card's ordering and may change when files are added.

| Action | Serial command or host wrapper |
| --- | --- |
| Browser root | `scripts/coco3_serial_test.ps1 -Command BrowserRoot` |
| F12 | `scripts/coco3_serial_test.ps1 -Command FunctionKey -Function 12` |
| Down / Up | `KD 1C`, `KU 1C` / `KD 1B`, `KU 1B` |
| Enter | `KD 30`, `KU 30` |
| Keyboard joystick | Pulse F8 (`FK 07`, `FK 06`) to cycle normal → left → right → normal; Space=`1F` fire, Left=`1D`, Right=`1E` |
| Frame capture | `scripts/capture_video_serial.ps1 -Port COM5 -OutputDirectory build/test-output -Name <name>` |

The key codes and reply formats are defined in [SERIAL_API.md](SERIAL_API.md).
For an automated BIN launch/play session, use `scripts/test_zenix_serial.ps1`
or `scripts/test_astro_serial.ps1`; both already own COM5 and handle the key
pulse timing. Do not run a second serial client alongside either script.

## Disk tests

| Program | Browser path | Navigation from `/` on current SD card | At BASIC after mounting |
| --- | --- | --- | --- |
| Joust (512K) | `/COCO3/512/Joust/JOUST.DSK` | Down 9, Enter; Down 3, Enter; Down 7, Enter; Down 1, Enter | `DIR 0`, then `RUN"JOUST"` (`JOUST.BAS` is on the disk); allow loading through all seven chunks |
| Pac-Man (512K) | `/COCO3/512/PACMAN.DSK` | Down 9, Enter; Down 3, Enter; Down 9, Enter | `DIR 0`, then `RUN"PACMAN"` (`PACMAN.BAS` is on the disk); press Enter on its color/arrow configuration screen, wait through `NOW LOADING`, then press joystick fire to start the maze |
| Thexder | `/COCO3/128K/B/THEXDER.DSK` | Navigate by displayed names; folder contents may change | `DIR 0`, then use the disk's launcher shown in its directory |

For a serial BASIC command, use `TypeText` for the text, then pulse Enter
separately; `TypeText` does not append Enter. For example:

```powershell
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command TypeText -Text 'DIR 0'
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command KeyDown -Key 48
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command KeyUp -Key 48
```

Check that `DIR 0` has complete, legible filenames **and** plausible file
sizes. Then run the BASIC launcher, confirm the game gets past its title,
exercise input for at least 45 seconds, and confirm the CPU has not returned to
the BASIC idle loop (`A7D3`–`A7D7`) or frozen at one unexpected PC. A serial
frame capture is useful at the directory and during gameplay, but one frame
alone is not proof of a complete pass. Compare graphics against a known-good
capture of the *same* 512K version.

F8's joystick-mapping selection can survive a serial `RESET`. Do not assume
two F8 pulses always select the right joystick on a subsequent launch. If a
game displays "press joystick button" but Space does not start it, pulse F8
once and try again. In the September 22 BRAM-disk test, Pac-Man needed this
extra pulse after Joust. A responsive in-game screen is the verification.

Serial `RESET` returns the CoCo to BASIC without resetting the SD-management
processor. Use it before changing disks during an automated regression run.
Wait for `STATUS PC=A7D3`–`A7D7` before sending `ROOT` and F12.

The older known-good 512K gameplay references are in
`build/test-output/hybrid-512k-games/` when that local build directory exists.
The failing shared-SDRAM Joust directory capture is
`build/test-output/disk-regression/joust-dir.png`.

## Current hardware observations (2026-09-22)

The recovery build uses BRAM for the 160 KiB disk image and SDRAM only for the
upper 384 KiB of CoCo RAM. On COM5, Joust mounted and loaded all seven chunks;
its game screen responded to joystick input. Pac-Man mounted, passed its BASIC
launcher and configuration screen, and reached the maze after the correct F8
joystick mode was selected. These runs are saved as PNGs in
`build/test-output/disk-regression/` (`joust-after-input-bram.png` and
`pacman-after-mode-bram.png`). The oversized `J` and stylized filenames in
Joust's directory are intentional game artwork, as confirmed on hardware by
the user; they are not directory corruption. Both are 160 KiB images; 360 KiB
support is paused in this recovery build and needs a separate regression.

## Direct BIN tests

| Program | Browser path | Launch |
| --- | --- | --- |
| Patched Zenix | `/BIN/ZENIX.BIN` | From current root ordering: Up 3, Enter; Up 2, Enter. Or run `scripts/test_zenix_serial.ps1`. |
| Astro | `/BIN/ASTRO.BIN` | From current root ordering: Up 3, Enter; Up 3, Enter. Or run `scripts/test_astro_serial.ps1`. |

`BIN READY ... EXEC ...` only verifies preparation. Wait for `BIN STARTED`,
then verify the expected screen, input, and sustained CPU progress. For Zenix,
the existing serial test plays for 45 seconds and checks PC and GIME state.

## Build/flash regression gate

Run `scripts/test_coco3_hybrid_512k_ram.ps1` and the relevant FDC integration
tests before a build. Build the normal bitstream at the **fixed** output path
`build/wukong/wukong_coco3_elite.bit`, then flash that exact file. A passing
RTL testbench is not enough: mount Joust or Pac-Man from `/COCO3/512` and
complete the disk procedure above. If the disk test fails, report the build as
failing even if a title or partial directory is visible. Do not overwrite or
commit a known-good release bitstream as part of this check.
