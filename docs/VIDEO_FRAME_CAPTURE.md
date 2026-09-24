# Full-resolution video capture

The Wukong build can capture the final visible HDMI frame over the CH340N
debug serial port. This is intended for automated screen validation as well
as visual debugging.

## Captured image

- Native active resolution: 640 by 480 pixels.
- Pixel format on the wire: RGB332 (one byte per pixel).
- PNG output: 640 by 480, converted to 24-bit RGB without spatial scaling.
- Source: the final HDMI RGB path, after CoCo video modes, palette and artifact
  processing, raster alignment, and the management OSD.

RGB332 keeps the capture buffer small enough for the current FPGA build. It
reduces color precision but does not reduce image resolution.

## Capture command

With the FPGA running and its debug USB serial interface on COM5:

```powershell
.\scripts\capture_video_serial.ps1 -Port COM5 -Name current-screen
```

The command writes three files under `build/test-output/screenshots/`:

- `current-screen.png` - full-resolution image.
- `current-screen.rgb332` - exact bytes received from the FPGA.
- `current-screen.json` - dimensions, CRC32, serial status, and validation
  metadata.

The FPGA sends a CRC32 after every frame. The script rejects a truncated or
corrupted serial transfer. A capture takes roughly 8 to 10 seconds at 460800
baud. The CoCo CPU is held while the stripes are captured and transferred so
that one PNG does not combine unrelated frames; the RV32 manager and disk
cache remain active.

## Reference-image validation

Use a known-good PNG to verify that the machine reached the expected screen:

```powershell
.\scripts\capture_video_serial.ps1 `
    -Port COM5 `
    -Name current-screen `
    -ReferencePng .\build\test-output\screenshots\expected-screen.png `
    -PixelTolerance 0 `
    -MaxDifferentPercent 0
```

`PixelTolerance` is the allowed per-channel difference. A nonzero tolerance
is useful when validating artifact-color output or captures from a mode whose
colors may vary slightly. `MaxDifferentPercent` sets the maximum percentage
of pixels that may exceed that tolerance. The command fails when the reference
does not match, making it suitable for scripted hardware tests.

## Serial protocol

The complete request/response interface, including keyboard injection, reset,
status, asynchronous trace messages, and error handling, is documented in
[SERIAL_API.md](SERIAL_API.md).

The host sends `CAPTURE` followed by a carriage return. Firmware replies with:

```text
FRAME BEGIN 640 480 RGB332 307200
<307200 binary pixel bytes, left-to-right and top-to-bottom>
FRAME END CRC32 XXXXXXXX
```

The capture hardware stores one 640-by-60 stripe at a time. Firmware requests
and transmits eight stripes while keeping the CoCo CPU halted. This provides a
complete 640-by-480 frame without requiring another full-frame block-RAM
allocation.

## Automated checks

Run the capture RTL test with:

```powershell
.\scripts\test_video_frame_capture.ps1
```

The manager MMIO regression also verifies capture requests, stripe selection,
status, address reads, and address auto-increment:

```powershell
.\scripts\test_manager_sd_mmio.ps1
```
