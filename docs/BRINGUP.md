# Wukong standalone HDMI bring-up

## Build

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

## Hardware acceptance test

1. Power the Wukong normally and connect its programmer.
2. Connect an HDMI display to the onboard HDMI output.
3. Program `wukong_hdmi_test.bit` into the FPGA over JTAG.
4. Confirm a stable 640x480 image containing color bars, a lower checker/gradient
   area, a white grid, and a white border.
5. Power-cycle and repeat before integrating any CoCo logic.

No PMOD wiring, keyboard, SD card, DDR3, Ethernet, UART interaction, button, or
switch is used. The image begins automatically after configuration and MMCM
lock.

## Verification status

Vivado 2025.2 successfully synthesized, placed, routed, checked, and generated
the XC7A100T bitstream on 2026-08-23. The routed timing report shows WNS
28.670 ns, WHS 0.184 ns, no failing endpoints, and no unconstrained path group.
The routed DRC report contains zero checks.

The physical HDMI acceptance test passed on 2026-08-23: after JTAG
configuration, the onboard HDMI output produced the expected stable test
pattern without PMOD wiring or any input peripheral. The standalone Wukong
HDMI checkpoint is complete.
