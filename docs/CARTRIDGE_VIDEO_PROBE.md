# Cartridge video probe

Run `RUN "VIDPROBE"` from drive 0, or select **B** in `TESTMENU`.
Start from ordinary Disk BASIC, not from inside the cartridge. This test uses
`CLEAR 200,&H5FFF` and loads `VIDHELP.BIN` at $6000; save your BASIC work first.

The six cases run in sequence, without changing the bitstream between cases:

| Case | Controlled variation |
| --- | --- |
| 1 | 40-column native text, FF90=$00, FF98=$03, FF99=$24, FF9D/E=$E040; retains existing scroll and horizontal offset |
| 2 | Same, with FF9B, FF9C and FF9F cleared |
| 3 | 40 columns with color attributes, FF99=$25 |
| 4 | 80 columns without attributes, FF99=$34 |
| 5 | 32-column native text without attributes, FF99=$20 |
| 6 | 40 columns at logical $1200 instead of $0200, FF9D/E=$E240 |

Each case prepares 25 rows of repeating A–Z characters. Rows restart at A;
the final character depends on the column count. The helper uses contrasting
palette entries. Case 1 reproduces the cartridge menu's principal mode/base
settings, **not its entire startup sequence or palette**.

Press a key to start each case. After viewing it, press a key to return; a
bounded timeout also returns (duration depends on processor speed). Answer Y/N
for whether the text is clear and the expected width. Report the six summary
rows, or photograph that one summary screen.

## Automatic and visual results

The helper verifies its generated screen bytes and reads back FF90, FF98,
FF99, FF9D and FF9E. The BASIC wrapper checks its completion marker.

- CHECK 0: automatic checks passed.
- Error bit $01: mode/base register mismatch.
- Error bit $02: screen pattern memory mismatch.
- Error bit $04: unsafe helper mapping or invalid case; no video test performed.
- Error bit $08: completion marker missing.
- VISUAL 1: you answered Y; VISUAL 0: you answered N.

A register/RAM PASS does **not** prove the video renderer fetched the right
bytes. That distinction is intentional: passing automatic checks with bad
visual output narrows investigation toward the video path.

## Safety and regression coverage

The helper masks IRQ/FIRQ and makes no BASIC or ROM calls while changing the
memory map. It backs up/restores the 4 KiB screen area, video registers,
palette, keyboard column latch and INIT0, then returns to Disk BASIC's all-RAM
mapping. Code/private stack occupy $6000–$6FFF; backup uses $7000–$7FFF.
It requires the normal Disk BASIC mapping for the helper's code page. It is
not a general launcher for arbitrary MMU configurations or active disk I/O.

`scripts/test_video_probe.ps1` executes the shortened-timeout helper on the
repository's CPU09 core with a flat RAM/register model. It checks all six
returns, restored screen bytes/registers, and rejection of an unsafe code-page
mapping. This is a software regression, not a GIME/MMU or rendered-video
simulation. Hardware visual results remain required.

`scripts/create_test_disk.ps1` assembles the normal helper and packages both
files into `disks/fpgatest.dsk`. The generated disk remains ignored by Git.
The original V1 probe batch made no production RTL changes; V2 accompanies
the focused native-text fetch correction described below.

## V2 corrections and fetch regression

V1 hardware results were CHECK=0 and VISUAL=0 for all six cases. Its case 4
incorrectly used $2C rather than $34 for 80 columns. Case 3 used attribute $12,
whose foreground palette A was not initialized by the probe. V2 uses $0A
(foreground palette 9, background palette 2), both explicitly initialized.
Those V1 cases must not be treated as independent proof of a hardware failure.

The native 32/40-column un-attributed fetch did independently reproduce
`AACCEEGG` in simulation: the odd character reloaded the even character rather
than selecting the high byte already fetched. The fix adds native slow text to
the existing second-byte selection, leaving attributed text/graphics unchanged.
`scripts/test_native_text_fetch.ps1` exercises the real BRAM and video latches
for 32/40/64/80 columns with and without attributes, 25 rows each. It checks
row stride, character selection, attributes and the fast-text second glyph.
Raster counters are controlled in this test; it does not validate HDMI framing.

## Code change rationale (2026-09-02)

In `rtl/coco3vid.v`, both RAM-fetch implementations (the default and
`NEW_SRAM` branches) now include
`{COCO,BP,HRES[2],CRES[0]} == 4'b0000` in the existing second-byte selection
condition. This selects native, non-graphics, 32/40-column text without
attributes. When `PIXEL_COUNT[4]` selects the second character, the renderer
shifts `CHAR_LATCH_0[15:8]` into its low byte instead of loading the same RAM
word again. The BRAM interface returns two adjacent character bytes per word;
the second byte must be consumed before advancing to the next word.

Previously, words containing AB, CD, EF were rendered as AA, CC, EE. The
simulation reproduced an expected B ($42) being replaced by A ($41), then D
by C, matching the hardware report. This justified changing byte selection,
not the CPU's RAM writes, character ROM, palette, or HDMI timing.

The new predicate excludes attributed text and graphics and does not change
their existing fetch conditions. The same correction is present in both
fetch branches. The original fetch regression exercised the default branch,
but the Wukong build actually defines `NEW_SRAM`. The follow-up scroll fix
corrects the regression script to use that build configuration too.

Supporting changes:

- `tb/native_text_fetch_tb.v` and `scripts/test_native_text_fetch.ps1` add
  the BRAM/video-latch regression described above.
- `tb/asm/VIDPROBE.asm` corrects the 80-column register value and attribute
  byte; `tb/basic/VIDPROBE.BAS` identifies the corrected test as V2.
- `scripts/create_test_disk.ps1` assembles/packages the helper and BASIC
  wrapper; `tb/basic/TESTMENU.BAS` exposes the probe as option B.
- The helper execution regression checks safe return and restoration,
  independently of the fetch regression. Both passed before the V2 build.

No cartridge ROM, HDMI library, global scroll reset, or screen cropping
change was made for this fix. Earlier vector-page changes in the working
tree are separate from this native-text correction.

## Hardware result and remaining bottom-row bug

Tested build: `build/wukong/wukong_coco3_elite.bit`, generated
2026-09-02 at 07:42:15 local time, SHA-256:

```text
8D187C75C30A059288B760E8D0174FB19FB16788A094F29CBDF4E9CFECC56915
```

The build met all user-specified timing constraints. Hardware testing showed
most text errors corrected, including the cartridge video menu reached with
F3 then D. The remaining reported behavior is:

- Probe case 1: last row contains carets (`^^^^`) followed by garbage.
- Probe cases 2–6: bottom rows are correct.
- Cartridge F3 → D menu: mostly corrected, but its last row is still corrupt.

The difference between probe cases 1 and 2 is preservation versus clearing
of FF9B (video bank), FF9C (vertical fine scroll), and FF9F (horizontal offset /
virtual-screen enable). This implicates preserved register state or its
interaction with row addressing, but does **not** identify a particular
register, prove the cartridge has the same values, or establish that the
remaining issue is an RTL defect rather than test-buffer/scroll interaction.
V1's CHECK=0 results did not verify those three preserved values.

Next investigation: capture those register values and trace the first and
last displayed row addresses with each value varied independently. Include
natural raster progression, which the isolated fetch regression does not
exercise. Do not clear these registers globally to hide the symptom; software
may legitimately use banking, scrolling, or a virtual-screen stride.

## V3: missing title and corrupt bottom row

The user additionally confirmed that the cartridge menu's top title was
missing. Boot simulation with the selected ROM captured FF9B=$00,
FF9C=$0F, FF9F=$00. This is simulated startup state, not a hardware readback
from the cartridge itself.

The renderer previously clamped an out-of-range vertical-scroll value to
`LINES_ROW`, which is the last scanline index (7 for eight-line text). Thus
$0F skipped seven scanlines of the first row and exposed the next row beyond
the 25-row screen buffer. The new frame initialization uses valid indices
unchanged and maps out-of-range values to zero. Register readback is not
changed, and valid smooth scrolling remains available. This agrees with
[MAME's GIME new_frame implementation](https://github.com/mamedev/mame/blob/master/src/mame/trs/gime.cpp),
which resets a scroll value at or above the row height to zero.

`tb/native_text_scroll_tb.v` uses natural raster counters, HSYNC, and vertical
blanking rather than forcing row addresses. Its 15 cases cover valid and
out-of-range scroll values for 1-, 2-, 8-, 9-, 10-, and 11-line rows over a
200-line field. The original RTL failed the out-of-range cases. The test also
exposed a separate 11-line row boundary error: index A advanced to B instead
of starting the next row. The index-A handler now ends an 11-line row while
retaining the existing index-B path for twelve-line legacy text.

Run with `scripts/test_native_text_scroll.ps1`; both this regression and the
updated fetch regression compile with `NEW_SRAM`, matching the board build.
V3 of the BASIC probe also prints the entry FF9B/FF9C/FF9F values in its
summary. Its first case remains unchanged, preserving the values so the
hardware regression does not hide the defect by clearing scroll.

Hardware result: the user confirms the last-line issue is fixed in both
F3 → D and VIDPROBE. No cartridge ROM patch is used. The latest confirmation
does not separately report title visibility.

A separate horizontal clipping issue remains: the user reports only 38
characters in 40-column mode, with the 38th partially cut off, and 75 in
80-column mode. This is recorded separately from the resolved vertical-scroll
issue. The cause is not established; the next regression should check full
horizontal-line visibility through the video-to-HDMI path, not only character
latches and vertical row addresses.

Candidate bitstream generated 2026-09-02 22:46:59 local time at
`build/wukong/wukong_coco3_elite.bit`; all user-specified timing constraints
met. Both regressions above passed. SHA-256:

```text
5E43636FFCA77A6D328A8D7725230A7BD2C5193DE597B079369693438A084E69
```

## Horizontal HDMI window correction

After the vertical fix, hardware showed only 38 complete characters in
40-column mode and 75 in 80-column mode. A full-chain test using the actual
GIME renderer, NTSC and CRT stages, Wukong integration, and hdl-util HDMI
raster measured 629 source pixels inside HDMI's active area and 11 pixels
arriving after it in both wide modes. Character-fetch tests had passed because
the loss occurred after fetching and rendering.

`rtl/wukong/wukong_top.v` now resynchronizes the source at HDMI x=781 instead
of 792. The GIME's 16-clock left edge plus the three-clock RGB/control pipeline
then aligns its 640-pixel content with HDMI x=0..639. This changes integration
phase only; the hdl-util HDMI library is unmodified.

The 32-column source is 512 pixels wide and uses a delay for independent
centering. Its delay is increased from 56 to 64 clocks so it remains centered
after shifting the shared raster phase. `tb/hdmi_window_tb.sv` and
`scripts/test_hdmi_window.ps1` verify:

```text
40-column HRES: 640 visible, 0 blanked
80-column HRES: 640 visible, 0 blanked
32-column HRES: 512 visible, 0 blanked
```

The test substitutes only clock, differential-output, and TMDS serializer
shells; the serializer does not affect raster coordinates or the RGB active
window. The actual HDMI raster and channel inputs remain under test.

Hardware confirmed that WIDTH 32 is centered correctly, but also exposed a
remaining integration limitation: WIDTH 40 and WIDTH 80 occupy all 640 active
HDMI pixels with no safety border. One monitor clips part of the final cell;
another clips one or two cells on the left and two or three on the right. The
digital window is no longer dropping source pixels, but full-width content is
still vulnerable to sink overscan. The proposed follow-up is a supported
720x480 HDMI raster with the 640-pixel GIME image centered inside it.
