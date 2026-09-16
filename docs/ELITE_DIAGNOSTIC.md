# Automated hardware diagnostics

The project supplies two self-contained 6809 diagnostics for the CoCo 3 Elite
FPGA core. They cover the deterministic parts of the FPGATEST disk in assembly
and add checks patterned after computer diagnostic cartridges: CPU behavior,
ROM integrity, RAM data/address faults, MMU banking, GIME state, and basic I/O
register paths. No ZIADIAG or Tandy diagnostic code is copied.

Both programs use native 80-column text, indent each result by ten columns,
use mixed upper- and lower-case descriptions, and report explicit `PASS` or
`FAIL` status. Machine-readable records are also emitted through the passive
UART mailbox.

## Build and run

From the repository root:

```powershell
.\scripts\build_elite_diagnostic.ps1
```

This produces:

- `build/diagnostics/ELITEDIAG.BIN`: fast, non-destructive system diagnostic
  for direct launch from the F12 browser.
- `build/diagnostics/ELTDIAG.BIN`: identical 8.3-name alias for copying to a
  FAT32 SD card and matching the filename stored in the diagnostic DSK.
- `build/diagnostics/ELITEMEM.CCC`: destructive, cartridge-resident 128 KiB
  memory diagnostic for F12 launch.
- `build/diagnostics/ELITETST.DSK`: disk containing the quick diagnostic as
  `ELTDIAG.BIN`, runnable with `LOADM"ELTDIAG":EXEC`.

`scripts/create_test_disk.ps1` also adds `ELTDIAG.BIN` to
`disks/fpgatest.dsk`. The memory cartridge is not put in the DSK: copy
`ELITEMEM.CCC` to the FAT32 SD card and select it from F12.

## Fast system diagnostic

`ELITEDIAG.BIN` runs 22 non-destructive tests in four groups:

- CPU and memory: arithmetic, indexed addressing, stack and branch behavior,
  direct-page/register transfers, base-RAM patterns, inactive MMU registers,
  active MMU bank isolation and task-zero/task-one switching. The separate
  ROM-resident memory cartridge safely covers all sixteen physical pages.
- System ROM and vectors: reset/interrupt vectors, ROM write protection,
  complete 16-bit additive signatures of Color BASIC, Extended Color BASIC,
  Disk Extended BASIC, and Super Extended BASIC, plus fixed-versus-mapped
  vector-page RAM, plus SAM ROM/all-RAM overlay switching and restoration.
- Video and GIME: 80-column screen RAM, native-mode state, all 16 palette
  entries and six-bit masking, border/scroll/HVEN registers, 1987 timer
  expiry through both FIRQ and IRQ status paths, read-to-clear behavior, and
  horizontal/vertical border status.
- Audio, storage and serial: PIA data-direction registers, the PIA audio-DAC
  latch, non-destructive FDC register access, and a known serial telemetry
  pattern.

Results are paged rather than allowed to scroll off the 25-row display. The
bottom row prompts for a key, and the next page retains the ten-column indent,
mixed-case text, and group layout. The HDL regression supplies that key and
checks the prompt, continuation page, all 22 result records, and final summary.

The complete ROM signatures deliberately identify the ROM set used by this
build. A legitimate alternate ROM revision needs its own expected signatures;
it should not be silently accepted as the tested image.

The program does not call BASIC or ROM routines after entry and needs no
mounted disk. It leaves interrupts masked and stops at its result screen; use
Ctrl-Alt-Delete to return to BASIC.

## Full 128 KiB memory diagnostic

`ELITEMEM.CCC` executes from the `$C000-$DFFF` ROM-Pak window, so it can test
every implemented RAM location without overwriting its own instructions. Its
menu provides:

- `Q` — quick suite: walking-one/walking-zero data-bus checks, independence of
  all sixteen physical 8 KiB pages, full-memory `00`, `FF`, `AA`, and `55`
  patterns, and word-address uniqueness.
- `L` — long suite: ascending and descending March C- read/write transitions
  across all sixteen pages, aimed at stuck, transition, alias, and coupling
  faults.
- `A` — run both suites.

The selected suite erases all 128 KiB of CoCo RAM. It keeps its mode and fault
state in CPU registers while destructive loops run, blanks the display, and
reconstructs the 80-column result screen afterward. Reset or launch another
file when finished; do not run it while unsaved BASIC work matters.

This is a MemTest2023-style pass/fail test rather than a copy of that program.
The quick suite is suitable for routine regression. The long March suite is
the stronger hardware soak check and takes noticeably longer on a real CoCo
clock.

## Automated result channel

The FPGA UART monitor observes writes to `$FF70-$FF77` without feeding data
back into the 6809 bus. Common records are:

| Marker at `$FF70` | Meaning |
| --- | --- |
| `$44` | Completed test; `$FF71` is number and `$FF72` is result code |
| `$53` | Final summary; `$FF71`, `$FF73`, and `$FF74` are total, pass, fail |
| `$4D` | Memory-test menu ready |
| `$50` | Memory suite start; `$FF71` is `$40` quick, `$80` long, `$C0` all |
| `$51` | Memory phase complete; `$FF71` is phase and `$FF72` is result |
| `$52` | First memory failure; page/address/value are in `$FF73-$FF77` |
| `$54` | March initialization completed |

The record marker is written last, making the preceding bytes an atomic
snapshot. `scripts/analyze_gime_serial.ps1` decodes these records. Periodic
hardware UART snapshots may coalesce fast intermediate records; the stable
`$53` summary is authoritative, while the HDL tests observe every write.

## Automated regressions

Run the non-destructive diagnostic through the production direct-BIN loader:

```powershell
.\scripts\test_elite_diagnostic.ps1
```

Run the memory cartridge and all menu paths:

```powershell
.\scripts\test_elite_memory_diagnostic.ps1
```

The default runs the full Quick suite, the full Long suite, and verifies the
All menu selection. Individual or menu-only runs are also available:

```powershell
.\scripts\test_elite_memory_diagnostic.ps1 -Suite Quick
.\scripts\test_elite_memory_diagnostic.ps1 -Suite Long
.\scripts\test_elite_memory_diagnostic.ps1 -Suite All
.\scripts\test_elite_memory_diagnostic.ps1 -Suite Menu
```

The regressions execute the real MC6809, MMU, dual-port RAM, and cartridge
datapath at the production CPU cadence. Their temporary Vivado workspaces are
removed after each run; the user-facing BIN, CCC, DSK, and listings remain in
`build/diagnostics`.

## Coverage compared with FPGATEST and classic diagnostic carts

The deterministic CPURAM, ROMTEST, GIMETEST, PALTEST, GIMETMR, and VECTEST
checks now have assembly equivalents. The memory cartridge adds the kind of
data-line, address-line, chip/page-isolation, pattern, and March testing found
in mature machine diagnostics such as C64 cartridges, adapted to the CoCo 3's
sixteen physical 8 KiB pages and GIME MMU.

Tests that need an external observer cannot honestly self-report PASS yet.
These include pixel-perfect monitor output, audible analog/HDMI sound,
joystick directions and buttons, cassette, printer, RS-232 PAK, and physical
floppy signals. The FPGATEST visual/audio/input programs and focused RTL tests
remain appropriate for those paths. A future PMOD loopback harness could turn
external connector checks into automated PASS/FAIL results; until then they
should be reported as manual or unsupported, never as false passes.

## What PASS means

Most checks write and read data end-to-end through the 6809 bus. The audio
test proves that PIA writes reach the software-visible DAC latch, not that a
speaker produced sound. The serial test proves that the mailbox pattern was
issued; simulator or UART capture verifies external observation. Likewise,
the visible report is a useful monitor check while the regressions separately
verify its display-memory contents and GIME configuration.
