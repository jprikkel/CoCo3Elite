# CoCo3Elite Wukong bring-up

## Current build and acceptance

The current machine boots Disk Extended Color BASIC 2.1 using 128 KiB BRAM,
PS/2 keyboard, and the ZIA diagnostic cartridge. Prepare local system/Disk
BASIC ROMs and supply `roms/ziadiag.ccc` as described in
[ROM preparation](../roms/README.md), then run from the repository root:

```powershell
& .\scripts\prepare_coco3_rom.ps1
& .\scripts\prepare_disk_rom.ps1
& .\scripts\build_wukong.ps1 -Mode HDMI_COCO_AUDIO
```

Program `build/wukong/wukong_hdmi_coco_audio.bit` through JTAG. For optional
read-only embedded drive 0/1 images, supply local untracked `fpgatest.dsk`
and `games.dsk`, then add `-EmbeddedTestDisks`; see [disk workflow](../disks/README.md).
MicroSD initialization and sector-zero reads do not provide FAT32 DSK mounting.

Use J14 pin 1/P23 for PS/2 data and pin 3/T24 for clock. Check BASIC typing,
Break, guarded Ctrl+Alt+Delete reset, F3 cartridge entry, 32/40/80-column mode
changes, and F7/F8 keyboard joysticks. Verify DIR/LOAD only when disks are
embedded. Record source revision, ROM hashes, bitstream hash, timing reports,
display model/settings, and separate visual and audio results.

The current hardware audio result is silence despite simulated packets.
Graphics-border behavior, monitor overscan of wide text, and diagnostic
GIME/MMU compatibility remain open. A successful build or simulation is not
a new hardware acceptance result. See [current implementation](CURRENT_IMPLEMENTATION.md)
for all seven modes and [compatibility status](DIAGNOSTIC_COMPATIBILITY_PLAN.md).

## Historical standalone and early core checkpoints

The following records describe the earlier 2026-08-23 tests. Their timing
figures and acceptance results belong to those bitstreams, not every current mode.

### Historical build

Use a Vivado release supporting Artix-7. On this Windows workstation, from the
repository root run:

```powershell
& scripts/build_wukong.ps1
```

The default remains the verified standalone test pattern. To build the Stage 1
legacy CoCo video checkpoint instead, run:

```powershell
& scripts/build_wukong.ps1 -Mode COCO_VIDEO
```

That mode produces `build/wukong/wukong_coco_video.bit`. It uses the original
CoCo video timing and character generator with a synthetic read-only text
screen; it does not yet contain the CPU, system ROM, keyboard, or writable main
RAM.

Physical acceptance passed on 2026-08-23. The board displayed green 80-column
text on a dark background with the expected `COCO3FPGA ARTIX-7`,
`QMTECH WUKONG VIDEO OK`, and `STAGE 1 PASSED` messages. This confirms the
portable character ROM, legacy video fetch path, palette adapter, sync/blanking,
and TMDS output are operating together on hardware.

To build the Stage 2 CPU and 128 KiB BRAM diagnostic:

```powershell
& scripts/build_wukong.ps1 -Mode CPU_DIAGNOSTIC
```

Program `build/wukong/wukong_cpu_diagnostic.bit`. A successful CPU execution
displays `CPU09 128K BRAM OK`, `RESET VECTOR PASSED`, and `STAGE 2 RUNNING`.
This image uses a repository-owned diagnostic ROM and does not contain BASIC.
Run `scripts/test_cpu_diagnostic.ps1` for the mixed-language CPU/BRAM test.

Physical Stage 2 acceptance passed on 2026-08-23. The Wukong displayed all
three expected messages, confirming reset-vector fetch, 6809 execution, both
128 KiB BRAM byte lanes, concurrent video reads, and HDMI output on hardware.

### Historical Stage 3 ROM preparation

The real boot image is user-supplied and is never committed. Place a legally
obtained CoCo 3 system ROM at `roms/coco3.rom`, then run:

```powershell
& scripts/prepare_coco3_rom.ps1
```

The script accepts a raw 32 KiB image or the historical 32,258-byte CoCo3FPGA
flash format. For the latter, it removes the `$8000` load header and recreates
the vector page from the original `FFF0.mif` behavior. It rejects an incorrect
format or reset vector, reports the source ROM SHA-256, and creates the ignored
Vivado input `build/roms/coco3.mem`. Use `-ExpectedSha256` to enforce the source
digest for reproducible builds. The real-boot RTL and `COCO3_BOOT` selector are now implemented; the current
workflow above also requires Disk BASIC and diagnostic cartridge inputs.

The launcher defaults to `C:\AMD\2025.2\Vivado\bin\vivado.bat`, selects the
bundled Tcl Store to avoid the corrupt per-user catalog, and invokes the Tcl
build. On another system, invoke `scripts/build_wukong.tcl` directly or pass a
different `-Vivado` path to the launcher.

The script performs synthesis, optimization, placement, physical optimization,
routing, timing and DRC reporting, and bitstream generation. Outputs are placed
under `build/wukong/`; the bitstream is:

```text
build/wukong/wukong_hdmi_test.bit
```

The build refuses to generate a bitstream when the worst timing path has
negative slack. Review `timing_summary.rpt` and `drc.rpt` even after a passing
run.

### Standalone test-pattern acceptance

1. Power the Wukong normally and connect its programmer.
2. Connect an HDMI display to the onboard HDMI output.
3. Program `wukong_hdmi_test.bit` into the FPGA over JTAG.
4. Confirm a stable 640x480 image containing color bars, a lower checker/gradient
   area, a white grid, and a white border.
5. Repeat after reprogramming if configuration is lost on power-cycle; persistent
   flash boot is not provided by this workflow.

No PMOD wiring, keyboard, SD card, DDR3, Ethernet, UART interaction, button, or
switch is used. The image begins automatically after configuration and MMCM
lock.

### Recorded standalone verification

Vivado 2025.2 successfully synthesized, placed, routed, checked, and generated
the XC7A100T bitstream on 2026-08-23. The routed timing report shows WNS
28.670 ns, WHS 0.184 ns, no failing endpoints, and no unconstrained path group.
The routed DRC report contains zero checks.

The physical HDMI acceptance test passed on 2026-08-23: after JTAG
configuration, the onboard HDMI output produced the expected stable test
pattern without PMOD wiring or any input peripheral. The standalone Wukong
HDMI checkpoint is complete.
