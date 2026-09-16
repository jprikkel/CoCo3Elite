# GIME reference tests

The directed tests in this suite encode behavior documented by
[Sock Master's GIME register reference](https://www.6809.org.uk/twilight/sock/gime.html).
They are intended to distinguish hardware-compatibility requirements from
project-specific extensions inherited from CoCo3FPGA.

Run the suite with:

```powershell
.\scripts\test_gime_reference.ps1
```

Test the same executable through both supported loading paths with:

```powershell
.\scripts\test_gime_load_paths.ps1
```

Build and run the serial-instrumented 1987 GIME hardware probe with:

```powershell
.\scripts\test_gime_hardware_probe.ps1
```

See [GIME_HARDWARE_PROBE.md](GIME_HARDWARE_PROBE.md) for the raster phases,
the direct-entry state recorder, the Boink-style dynamic-LPR test, UART field
definitions, and the DSK-versus-direct-BIN comparison.

The suite contains four independent test benches:

- `gime_reference_timer_tb.v` verifies the 1987 GIME `value + 1` countdown,
  periodic reload, FF94/FF95 write behavior, fast/slow source selection,
  blink toggling, one-cycle expiry, and the documented timer-zero stop rule.
- `gime_reference_interrupt_tb.v` verifies the six FF92/FF93 source bits,
  pending latches, source masks, INIT0 master gates, and independent
  read-to-acknowledge behavior.
- `gime_reference_sync_cadence_tb.v` verifies that doubled HDMI transport
  scanlines do not double the GIME HBORD interrupt or FF91 slow timer rate.
- `gime_reference_video_tb.v` verifies the documented HRES row strides,
  HVEN's 256-byte virtual row, LPR decoding and infinite graphics row, normal
  LPF heights, and raster-dependent LPF=`10` zero/infinite behavior.

The video test counts doubled FPGA transport lines: 192, 200, and 225 CoCo
scanlines therefore correspond to 384, 400, and 450 renderer lines.

## DSK and direct BIN parity

`GIMEREF.asm` builds as a standard DECB binary at `$6000`. It programs native
graphics, LPF/LPR, HRES/CRES, border, scroll, display-start, HVEN/horizontal
offset, and timer registers before writing a completion sentinel.

- `gime_reference_bin_load_tb.v` streams that executable through the real
  management BIN-loader ROM and FIFO into the real 6809 machine.
- `gime_reference_dsk_load_tb.v` serves a generated DECB disk through the
  production FDC backend. A test-only 6809 ROM-Pak reads the executable from
  its deterministic ToolShed-allocated sector, validates the DECB header,
  loads it into RAM, and jumps to
  the same entry point. This avoids making the regression depend on keyboard
  debounce timing while retaining the actual CPU/FDC/sector-buffer path.

Both benches check the final GIME register state. This makes a path-specific
failure visible without conflating it with the separate raster conformance
failures above.

The production BIN-loader regression also verifies the Color BASIC `EXEC`
entry contract. This is important for older programs whose startup code assumes
the register state left by the ROM command dispatcher: `A=$00`, `B=$44`,
`X=$ABAB`, `DP=$00`, zero set, IRQ/FIRQ enabled, and BASIC's existing stack.
Sound with missing graphics only on the direct path is therefore treated first
as a launch-context failure, not as evidence of a renderer defect.

The suite is deliberately a conformance test. A failure identifies behavior
that differs from the reference and should not be converted into an expected
result merely to make the test green.
