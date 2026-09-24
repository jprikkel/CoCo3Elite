# CoCo3Elite USB serial debug interface

The Wukong V3 onboard CH340N USB-to-UART bridge provides the host connection
for CoCo 3 diagnostics and test automation. The FPGA transmits on package pin
E3 and receives on package pin F3. No PMOD connection or external USB-to-UART
adapter is required.

This page describes the physical interface and normal ways to connect to it.
The authoritative request/response command syntax, trace-field definitions,
keyboard injection, reset control, and video-capture format are documented in
[Serial API](../docs/SERIAL_API.md).

Connect the board's Mini-USB serial connector and open its Windows COM port at
**460800 baud, 8 data bits, no parity, 1 stop bit, no flow control**. For COM3:

```powershell
.\tools\putty\putty.exe -serial COM3 -sercfg 460800,8,n,1,N
```

For a bounded non-interactive trace capture (currently detected board:
`COM5`):

```powershell
.\scripts\capture_serial_debug.ps1 -PortName COM5 -Seconds 8
```

Close PuTTY before using the capture script because Windows permits only one
process to open the serial port at a time.

Use the request/response test client for a liveness check or a single trace
snapshot:

```powershell
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command Ping
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command TraceSnap
```

The console reports `COCO3 UART READY`, cartridge enable/entry events, and
other manager activity. Repeating detailed traces are disabled after reset so
UART traffic cannot unnecessarily affect hardware tests. `TRACE SNAP` requests
one trace, while `TRACE ON` enables one snapshot per second until `TRACE OFF`.
A current trace resembles:

```text
PC=A7D5 K=0 R=FF C=FF S=A8 T=00 V=... G=CC005 M=... D=00020100 Q=00000000 J=40
```

Select a `.CCC` image from the F12 SD browser to install a ROM-Pak. The manager
cold-starts the CoCo while preserving the SD subsystem, then the system ROM
enters the cartridge through the emulated CART/FIRQ autostart path. A working
handoff adds `CARTRIDGE LOADED`, `CART ON`, and `CART ENTRY C000`; subsequent
PC snapshots help distinguish a running cartridge from a tight polling loop
or failed entry. `K` shows whether the PS/2 decoder sees any matrix key, while
`R` and `C` show the last PIA keyboard row read and column-select write.

The logger only observes existing debug signals and does not stall the CPU.
`S` is the live SD-manager status byte. The complete status and detail bytes
remain available to CoCo software at `$FF60` and `$FF61`. Card removal stops
cache writeback; reinsertion remounts FAT32 and refreshes the browser without
reloading the bitstream.
`PC` comes from the MC6809's existing `RegData` output. It is the CPU's
current program-counter register and may point past an instruction being
executed; it is not an instruction trace or an arbitrary bus address.

The final `J=` byte reports the decoded J10 digital-joystick inputs. After
reset, idle J10 on the right CoCo port is `J=40`; pressing F7 selects the left
port and changes idle to `J=00`. Direction and button bit assignments are in
the [Serial API](../docs/SERIAL_API.md) and the physical wiring is in the
[PMOD Atari joystick interface](pmod-atari-joystick-digital-interface.md).

This console is enabled in `COCO3_ELITE`. It is not DriveWire, a ROM console,
or an emulated CoCo RS-232 PAK. Host input is consumed only by the documented
management commands. Messages can be coalesced while transmission is busy, so
this is not a complete instruction trace.
