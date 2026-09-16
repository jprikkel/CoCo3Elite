# 1987 GIME hardware probe

`GIMERAST` is a focused visual and serial test for the later 1987 GIME. It is
intended to replace trial-and-error changes made from screenshots alone. The
test does not use BASIC or ROM routines after entry, and the same segmented
DECB executable is supplied both directly and inside a disk image.

Build and validate it with:

```powershell
.\scripts\test_gime_hardware_probe.ps1
```

The generated hardware files are:

- `build/gime_1987_probe/GIMERAST.BIN`
- `build/gime_1987_probe/GIMEINIT.BIN`
- `build/gime_1987_probe/GIMELPR.BIN`
- `build/gime_1987_probe/GIME1987.DSK`, containing all three programs

The regression executes the BIN through the production direct-BIN loader and
checks that all 16,000 framebuffer bytes arrive correctly before the program
publishes its first diagnostic record. The DSK contains that identical BIN for
comparison through Disk BASIC.

## Visual phases

Each phase lasts about two seconds. The border color identifies the phase.

| Phase | Test | Expected display |
| --- | --- | --- |
| 0 | Normal LPR | Alternating checkerboard rows |
| 1 | LPR=`111` infinite row | The first graphics row repeats vertically |
| 2 | HBORD-timed LPR changes | Stable horizontal regions switch between repeated and advancing rows |
| 3 | FF9F horizontal offset | The pattern moves horizontally in two-byte steps |

The program repeats these four phases continuously. It uses 320-by-200,
four-color native graphics at logical screen address `$2000`.

## Entry-state comparison

`GIMEINIT` makes no GIME changes. It immediately captures the environment in
which an `EXEC` begins. Run it from `GIME1987.DSK` with
`LOADM"GIMEINIT":EXEC`, then run the identical `GIMEINIT.BIN` directly from
the management menu. Its mailbox decodes as:

```text
49 ssss dp cc 90 91 ww
```

The fields are the entry stack pointer, direct-page register, condition-code
register, `$FF90`, `$FF91`, and BASIC's `$0071` warm-start byte. A difference
here proves that a DSK/BIN discrepancy exists before the demo programs touch
the GIME.

## Boink-style dynamic LPR test

`GIMELPR` reproduces the documented mechanism behind Sock Master's Boink
demo using generated test graphics. It alternates `$FF98` between normal rows
and LPR=`111` at selected HBORD counts. A horizontal band should stretch and
bounce vertically while the rest of the synthetic 256-by-192, 16-color image
remains stable. Its mailbox decodes as:

```text
42 ff ss ee hhhh 98 99
```

Here `ff` is the frame, `ss-ee` is the held scanline range, and `hhhh` is the
preceding frame's HBORD count. If this fails in both launch paths, the fault is
the renderer's dynamic LPR behavior rather than the direct BIN loader.

## Passive serial telemetry

The FPGA UART monitor observes the 6809 bus and renderer state. It does not
return data to the 6809, insert wait states, or modify RAM. Extended status
lines have this form:

```text
PC=.... K=. R=.. C=.. S=.. T=.. V=........................................ I=.. L=... Q=. B=. A=...... N=.... H=.... W=..:..@..../... M=................
```

The added fields are:

- `L`: current doubled HDMI transport line.
- `Q`: current GIME line-within-row counter (`VLPR`).
- `B`: `{SYNC_FLAG,HBLANK,VBLANK}` packed into the low three bits.
- `A`: current 21-bit GIME row-start address.
- `N`: number of writes to `$FF98-$FF9F` during the preceding second.
- `H`: logical CoCo HSYNC count during the preceding second. It should be
  approximately 15,734, rather than the doubled HDMI line rate.
- `W`: last GIME video-register write as `address:data@PC/renderer-line`.
- `M`: the eight-byte test mailbox written at `$FF70-$FF77`.

For `GIMERAST`, mailbox bytes are:

```text
47 pp ff hh ll 98 99 9f
```

Here `pp` is the phase, `ff` is its frame counter, `hhhh` is the measured
HBORD count in the preceding video frame, and the last three bytes are live
readbacks of `$FF98`, `$FF99`, and `$FF9F`.

## Comparing DSK and direct BIN launches

Capture at least 15 seconds for each path:

```powershell
.\scripts\capture_serial_debug.ps1 -Seconds 15 -OutputPath build\traces\gimerast-dsk.log
.\scripts\capture_serial_debug.ps1 -Seconds 15 -OutputPath build\traces\gimerast-bin.log
.\scripts\analyze_gime_serial.ps1 -Path build\traces\gimerast-dsk.log -ComparePath build\traces\gimerast-bin.log
```

The mailbox and video-state sequence should match between paths. A mismatch
before phase 0 identifies loader/startup state. Matching telemetry with a
visual failure instead points to renderer fetch or output timing.

The same capture procedure can be used around unmodified `DEMO.BIN` and
`BOINK.BIN`. Their `N` and `W` fields reveal whether direct loading changes
the sequence or raster phase of GIME writes.

## 1987 target

The conformance target is the 1987 GIME: timer values use the documented
`n+1` behavior. LPR=`111` is treated as an infinite graphics row, and
LPF=`10` is zero or infinite depending on whether it is selected during the
vertical border or active display. The automated reference suite remains:

```powershell
.\scripts\test_gime_reference.ps1
```

Reference: [Sock Master's GIME register reference](https://www.6809.org.uk/twilight/sock/gime.html).
