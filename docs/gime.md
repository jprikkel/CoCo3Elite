# GIME support

CoCo3Elite targets the later **1987 GIME** behavior while preserving CoCo 1,
CoCo 2, and CoCo 3 software compatibility. This document describes the
implemented behavior, the division between the CPU-facing GIME logic and the
video renderer, the automated coverage, and the known conformance gaps.

The primary behavioral reference is
[Sock Master's GIME register reference](https://www.6809.org.uk/twilight/sock/gime.html).
The Tandy technical references under `docs/` are also useful for the documented
machine interface. Undocumented behavior is treated as compatible only after a
directed regression or hardware test demonstrates it.

## Architecture

GIME behavior is split across three layers:

1. `rtl/core/coco3_boot_machine.v` implements the CPU-visible registers,
   memory map, MMU, ROM/RAM selection, interrupt routing, timer integration,
   palettes, and video-register storage.
2. `rtl/third-party/coco3fpga/coco3vid.v` renders legacy and native video from
   the stored GIME state. Project changes to this inherited renderer should be
   small, documented, and covered by a focused test.
3. `rtl/wukong/coco3_boot_system.v` and `rtl/wukong/wukong_top.v` adapt the
   renderer to the Wukong memory and HDMI pipelines. This includes palette
   expansion, narrow-mode centering, frame synchronization, optional artifact
   color, scanlines, the management OSD, and final RGB capture.

The normal 128 KiB reset region remains in dual-port block RAM. In the 512 KiB
hybrid build, GIME pages `$30-$3F` are backed by that proven 128 KiB BRAM and
pages `$00-$2F` use the upper 384 KiB in SDRAM. CPU accesses to upper memory
wait for SDRAM; video uses burst-filled line buffers and frame-start prefetching.

## CPU-visible register support

| Address | Function | Current support |
| --- | --- | --- |
| `$FF90` | INIT0 | Register read/write, MMU enable, IRQ/FIRQ master enables, ROM map selection, and vector-page selection are connected. |
| `$FF91` | INIT1 | Register read/write, MMU task selection, and fast/slow timer source selection are connected. |
| `$FF92` | IRQ enable/status | Six source latches, masks, master gate, routing, status readback, and read-to-acknowledge pass the directed interrupt test. |
| `$FF93` | FIRQ enable/status | Six source latches, masks, master gate, routing, status readback, and independent read-to-acknowledge pass. |
| `$FF94-$FF95` | Programmable timer | Register order, `n+1` countdown, periodic reload, fast/slow source selection, expiry pulse, and blink integration are present. Programming zero does not yet stop the timer as required. |
| `$FF98` | Video mode | Graphics/text selection and the renderer's legacy/native mode fields are connected and readable. |
| `$FF99` | Video resolution | HRES, CRES, LPF, and LPR fields are connected and readable. Normal row widths and normal vertical heights pass directed tests. |
| `$FF9A` | Border color | Six-bit border palette value is stored, readable, and rendered. |
| `$FF9B` | Vertical bank | Two implemented bank bits participate in the video start address and SDRAM frame prefetch. |
| `$FF9C` | Vertical scroll | Four-bit fine vertical scroll is stored, readable, and applied by the renderer. |
| `$FF9D-$FF9E` | Display offset | The 16-bit display start offset is stored, readable, and used for video fetches. |
| `$FF9F` | Horizontal offset/HVEN | Horizontal offset and the HVEN 256-byte virtual row are implemented. The directed stride tests pass. |
| `$FFA0-$FFAF` | MMU tasks 0 and 1 | Six physical page bits are implemented in the 512 KiB build. The 128 KiB build aliases higher pages modulo 16, like absent physical address pins. |
| `$FFB0-$FFBF` | Palette entries | Six-bit read/write values for all sixteen palette entries are implemented and expanded to HDMI RGB. |
| `$FFDE-$FFDF` | ROM/RAM map strobes | ROM and all-RAM selection are implemented, including cartridge visibility needed by diagnostics. |

Register storage and readback do not by themselves prove every undocumented
side effect. The support claims above are limited to behavior exercised by the
listed tests and hardware software.

## Video support

The renderer currently supports:

- CoCo-compatible text and graphics modes.
- Native 32-, 40-, 64-, and 80-column text layouts through the GIME HRES/CRES
  controls.
- Native graphics byte widths of 16, 20, 32, 40, 64, 80, 128, and 160 bytes
  per row.
- Normal 192-, 200-, and 225-line native displays. The renderer emits two HDMI
  transport lines for each logical CoCo scanline.
- LPR row heights of 1, 2, 8, 9, 10, and 11 lines and the infinite graphics-row
  form used by software such as Boink-style effects.
- HVEN's 256-byte virtual row, horizontal offset, vertical fine scroll, video
  bank, and programmable display start.
- Sixteen programmable six-bit palette entries, border color, text attributes,
  blink, and underline behavior used by the current software suite.
- Final 640-by-480 RGB capture through the serial management interface.

Artifact-color decoding, palette presets, scanlines, and the management OSD are
post-processing features around the GIME renderer. They are not replacements
for GIME register behavior and should be tested separately.

## Known conformance gaps

The following failures remain in `scripts/test_gime_reference.ps1`.

### Timer value zero

Writing `$000` to `$FF94-$FF95` must disable the timer. The current FF94 write
always enables it. The fix belongs in `rtl/core/coco3_gime_timer.v` and should
enable the timer only when the complete twelve-bit programmed value is nonzero.

### Logical HSYNC cadence

The HDMI renderer emits two transport scanlines per logical CoCo scanline. The
GIME HBORD source and slow timer currently consume raw `video_hsync`, allowing
the duplicate transport edge to trigger HBORD and advance the timer. Both must
use the filtered logical CoCo cadence represented by `pia_hsync`.

This is one integration fault reported by two assertions:

- A duplicate renderer HSYNC generates an HBORD event.
- A duplicate renderer HSYNC advances the slow timer.

### Dynamic LPF=`10`

The 1987 GIME treats LPF=`10` as a raster-dependent zero/infinite display:

- Selecting it during vertical blanking keeps the display blank.
- Selecting it during active video keeps video active across conventional
  vertical boundaries.

The current renderer instead treats LPF=`10` as a fixed 210-line mode, starting
near transport line 14 and blanking near line 434. Normal LPF values pass; only
this dynamic special case remains unsupported.

## Automated verification

Run the main conformance suite with:

```powershell
.\scripts\test_gime_reference.ps1
```

The suite has four independent groups:

| Group | Coverage | Current result |
| --- | --- | --- |
| Timer | 1987 `n+1` timing, reload, write order, source selection, blink, expiry, and zero-stop | **Fail:** zero-stop only |
| Interrupt | Six sources, masks, master enables, IRQ/FIRQ routing, pending state, and acknowledgement | **Pass** |
| Sync cadence | Logical HSYNC cadence for HBORD and the slow timer | **Fail:** raw doubled HSYNC reaches both consumers |
| Video | HRES stride, HVEN, LPR, normal LPF heights, and dynamic LPF=`10` | **Fail:** the two dynamic LPF=`10` assertions |

Additional focused regressions include:

```powershell
.\scripts\test_gime_load_paths.ps1
.\scripts\test_gime_hardware_probe.ps1
.\scripts\test_native_text_fetch.ps1
.\scripts\test_native_text_scroll.ps1
.\scripts\test_zenix_video.ps1
.\scripts\test_coco3_hybrid_512k_ram.ps1
```

The direct-BIN and DSK tests distinguish loader state from a real GIME defect.
The hybrid-memory test drives the real GIME raster into the SDRAM video cache;
after its cold frame, warm frames must complete without visible cache misses.

## Hardware diagnostics

The 115200-baud serial trace exposes the state needed to compare a working DSK
launch with a direct BIN or cartridge launch:

- `I0` and `I1`: `$FF90` and `$FF91`.
- `V`: `$FF98`, `$FF99`, `$FF9B`, `$FF9D-$FF9E`, `$FF9F`, all sixteen palette
  entries, and a current video-memory word.
- `G`: initialization and MMU flags.
- `M`: both MMU task register sets.
- `Q`: the hybrid video-cache miss count in the current sampled interval.

See [SERIAL_API.md](SERIAL_API.md), [GIME_TESTS.md](GIME_TESTS.md), and
[GIME_HARDWARE_PROBE.md](GIME_HARDWARE_PROBE.md) for commands and detailed
field definitions.

## Test-infrastructure limitation

The full HDMI-window simulation currently fails elaboration because XSIM does
not support the bidirectional `tran` primitive used by the synthesized SDRAM
bus connection. That is a simulation-infrastructure problem, not an additional
GIME conformance failure. The focused GIME and hybrid-memory benches do not
depend on that primitive.

## Completion criteria

GIME support can be called reference-clean when:

1. All four `test_gime_reference.ps1` groups pass without weakening their
   assertions.
2. DSK and direct-BIN loading produce identical final GIME/MMU state for the
   reference program.
3. The hardware probe agrees with the 1987 timing rules.
4. Existing cartridge, disk, direct-BIN, reset, 512 KiB memory, and HDMI image
   regressions remain functional.
