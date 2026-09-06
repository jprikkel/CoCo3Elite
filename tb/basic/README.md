# CoCo3Elite BASIC diagnostics

These ASCII Extended Color BASIC programs are packaged into the local
`disks/fpgatest.dsk` image by `scripts/create_test_disk.ps1`.

Generate the disk from the repository root after supplying local
`roms/MEMT2023.BIN` and `roms/SYSINFO.BIN`. The generator replaces
`disks/fpgatest.dsk` and assembles `VIDHELP.BIN` using bundled asm6809.
To use it on hardware, supply `disks/games.dsk` too and build with
`-EmbeddedTestDisks`; drive 0 is the diagnostic disk. All DSK inputs are
optional, read-only when embedded, and untracked. MicroSD cannot mount them yet.

From Disk Extended Color BASIC on drive 0, run the menu with:

```basic
RUN "TESTMENU"
```

The tests cover CPU arithmetic, BASIC array RAM, non-destructive installed-RAM
capacity detection from 64K through 512K, all five legacy PMODE graphics
modes, all four CoCo 3 HSCREEN graphics modes, HDMI audio, 32/40/80-column
display positioning, keyboard input, both joystick axes, and both fire buttons.

The disk also contains `MEMT2023.BIN` and `SYSINFO.BIN` as Disk BASIC binary
files. These are sourced from the ignored local `roms` directory when the disk
is generated. MemTest2023+ intentionally runs continuously until reset. These
third-party utilities also probe GIME timer, interrupt, and MMU behavior that
is not yet completely emulated, so a stall or blank display currently records
a compatibility gap rather than a failure of the diagnostic-disk generator.

`PALTEST.BAS` reports the live GIME palette, installs the standard RGB
palette, and displays labeled PMODE 1 and PMODE 3 four-color test bars for
both CSS color sets. This separates palette initialization faults from pixel
index/order faults without requiring long manual `PEEK` and `POKE` commands.

`GIMETEST.BAS` performs non-destructive, self-checking tests of the ROM's
recognized RGB or composite startup palette, palette RAM and six-bit masking,
the inactive MMU task, and
the readable GIME initialization registers. It prints hexadecimal register
values plus explicit `PASS` or `FAIL` results and restores modified state.

`ROMTEST.BAS` checks the system vectors, reset entry point, ROM write
protection, and Disk BASIC mapping. `CARTTEST.BAS` uses the project diagnostic
window at `$FF70-$FF73` to checksum the diagnostic ROM-Pak without launching
it. This distinguishes a corrupt or incorrectly mapped image from the
execution or compatibility defects; F3 CART/FIRQ autostart is hardware-verified.

`GIMETMR.BAS` and `VECTEST.BAS` probe timer and vector-page behavior;
`VIDPROBE.BAS` uses the assembly helper for six controlled native-text cases.
See [cartridge video probe](../../docs/CARTRIDGE_VIDEO_PROBE.md).

The capacity probe does not imply installed 512 KiB RAM: the current machine
has 128 KiB. AUDIO and the cartridge sound test are useful reproduction cases,
but HDMI audio may remain muted by a display until sustained nonzero samples
arrive after a power cycle. Graphics/border and diagnostic
GIME/MMU compatibility remain incomplete; a RAM/register PASS alone does not
prove correct rendered pixels or audible output.
