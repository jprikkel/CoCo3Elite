# Diagnostic cartridge compatibility plan

This plan tracks compatibility defects exposed by the ZIA Computing cocodiag
cartridge and related diagnostic programs. Cartridge autostart itself is
hardware-verified: F3 presents the ROM-Pak to an initialized machine, the
system ROM handles the CART/FIRQ edge, the cartridge reaches `$C000`, and its
main menu, keyboard, CPU, RAM, ROM, joystick, and sound tests run.

## Open bugs

| Priority | Area | Observed result | Expected result | Current evidence |
| --- | --- | --- | --- | --- |
| Resolved input | Super Extended BASIC ROM test | ZIA reports CRC `38E9 UNK` | ZIA identifies a known ROM revision | The host checker reproduces `38E9` exactly from the selected `coco3.rom`; `coco3p.rom` produces `0A99`. This is a ROM-revision identification issue, not evidence of an FPGA mapping failure. |
| Resolved bottom row | GIME video test: vertical scroll | User confirms the last-row issue is fixed in F3 → D and VIDPROBE | Correct bottom row | Out-of-range FF9C now starts at zero instead of clamping to the last glyph scanline. Fifteen scroll cases and eight fetch modes pass in NEW_SRAM. See [V3 details](CARTRIDGE_VIDEO_PROBE.md#v3-missing-title-and-corrupt-bottom-row). |
| P1 — digital window fixed; display margins remain | Horizontal text clipping | WIDTH 32 is correct; WIDTH 40/80 clipping now varies by monitor because their 640 pixels reach both HDMI active edges | All 40 or 80 columns fully visible on different sinks | Full-chain simulation measured and corrected 11 internally blanked pixels: frame resync x=792→781 produces 640 visible/0 blanked, and narrow delay 56→64 preserves 32-column centering. Hardware then showed sink-dependent clipping. Follow up with a 720x480 HDMI raster and center the 640-pixel GIME area with side margins. |
| P2 | Machine-language diagnostics | `MEMT2023.BIN` stalls near `$007C`; `SYSINFO.BIN` stalls near `$2EE0` or displays black | Programs complete or identify the implemented machine accurately | These programs exercise MMU, memory-size, interrupt, and GIME behavior beyond the BASIC tests. They are not evidence of a cartridge-launch failure. |
| P3 | Video edge artifact | A short horizontal green line has appeared left of the first row in some 40/80-column modes | Uniform border outside the active display | Previously recorded as an open video bug; determine whether it remains after the current HDMI integration before changing RTL. |

Printer, cassette, and CoCo serial tests are **not current bugs**. They require
physical interfaces that the Wukong implementation does not provide. The
onboard CH340N UART is a passive FPGA debug console, not the CoCo bit-banged
serial port.

## Phase 1: make failures reproducible

1. Record the exact cocodiag version and SHA-256 of every ROM used by a test.
2. Capture a baseline UART log for cartridge entry, ROM test, and video test.
3. Add a host-side cocodiag-compatible CRC tool for `$8000-$9FFF`,
   `$A000-$BFFF`, and `$E000-$FDFF`.
4. Calculate the expected CRC directly from `coco3.rom` and `coco3p.rom` before
   involving the FPGA. This separates an unknown ROM revision from an RTL
   mapping/read defect.
5. Add a short BASIC or 6809 test to write each relevant GIME register, read it
   back, and report PASS/FAIL without requiring long manual input.

Acceptance: each hardware failure has a deterministic test and expected value.

## Phase 2: fix the Super Extended BASIC CRC

1. Add simulation coverage for INIT0 ROM map values `00`, `01`, and `10`.
2. Verify that map `10` exposes internal ROM continuously from `$8000-$FDFF`
   while I/O and vector behavior remain correct.
3. Compare CPU-visible sequential reads from `$E000-$FDFF` against the prepared
   ROM byte-for-byte. Include page boundaries and the final `$FDFF` byte.
4. Check BRAM read latency at the CPU enable boundary; do not compensate by
   changing the ROM image.
5. Confirm the CRC in simulation and then on hardware with ZIA.

Result: the host checker and ZIA both report `38E9` for the selected
`coco3.rom`. A ROM that ZIA recognizes as `00FF NTSC` is a separate firmware
input; no RTL change is justified by the current CRC result.

## Phase 3: restore GIME video-register compatibility

Implement and test one register at a time, using `rtl/coco3fpga_dw.v` as the
behavioral reference:

1. Move the video-mode register state into `coco3_boot_machine` so CPU readback
   and renderer inputs come from one authoritative register set.
2. Implement `$FF98` fully: graphics/text mode, extended horizontal
   resolution, descriptor enable, monochrome, and lines per row.
3. Implement and read back `$FF99` mode fields.
4. Add `$FF9A` border-color storage/readback and feed it into the HDMI border
   path. Preserve the legacy bit-7 palette-update behavior where applicable.
5. Implement documented readback behavior for `$FF9B-$FF9F` and verify screen
   start, scroll, and horizontal offset.
6. Test all modes selected by cocodiag, including transitions back to its menu.

Acceptance: cocodiag's video menu remains stable, each selected mode is
recognizable, mode transitions do not shift or corrupt subsequent screens, and
the border color follows `$FF9A`.

## Phase 4: broaden GIME/MMU compatibility

1. Add read/write and reset-value tests for INIT0/INIT1, MMU task selection,
   all sixteen MMU registers, palette registers, and SAM all-RAM switching.
2. Implement only the interrupt/timer behavior required by an observed failing
   test, with a focused regression for each addition.
3. Re-run `MEMT2023.BIN` and `SYSINFO.BIN` with UART PC traces. Classify any
   remaining failure as 128-KiB capacity behavior or an MMU/GIME defect.

Acceptance: the BASIC GIME suite passes, supported diagnostics make forward
progress, and unsupported memory capacity is reported rather than hanging.

## Phase 5: hardware regression

Before another speculative cartridge-video change, run the six-case
[cartridge video probe](CARTRIDGE_VIDEO_PROBE.md). It separates automatic
register/RAM checks from visual results and batches mode, attribute, offset
and screen-base variations into one disk/build.

For every fix:

1. Run boot-machine, boot-video, and cartridge-trace simulations.
2. Build `HDMI_COCO_AUDIO` with the diagnostic disk embedded as drive 0.
3. Verify Disk Extended Color BASIC boot, 32/40/80-column transitions,
   keyboard, both keyboard joysticks, sound, F3 cartridge entry, ROM test, and
   video test.
4. Record the bitstream hash, ROM hashes, timing slack, and hardware results.

Do not combine speculative video, MMU, and interrupt changes in one step. Each
commit should fix one reproduced behavior and add its regression test.
