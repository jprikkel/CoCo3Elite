# CoCo3Elite USB serial diagnostics

The Wukong V3 onboard CH340N USB-to-UART bridge provides a passive debug
console for the CoCo 3 implementation. The FPGA transmits on package pin E3;
the bridge's receive path on F3 is intentionally unused for now.

Connect the board's Mini-USB serial connector and open its Windows COM port at
**115200 baud, 8 data bits, no parity, 1 stop bit, no flow control**. For COM3:

```powershell
.\tools\putty\putty.exe -serial COM3 -sercfg 115200,8,n,1,N
```

For a bounded non-interactive capture (currently detected board: `COM5`):

```powershell
.\scripts\capture_serial_debug.ps1 -PortName COM5 -Seconds 8
```

Close PuTTY before using the capture script because Windows permits only one
process to open the serial port at a time.

The console reports `COCO3 UART READY`, cartridge enable/entry events, and a
once-per-second CPU PC register snapshot plus keyboard state such as:

```text
PC=A176 K=0 R=FF C=FF S=81 D=00 V=...
```

Select a `.CCC` image from the F12 SD browser to install a ROM-Pak. The manager
cold-starts the CoCo while preserving the SD subsystem, then the system ROM
enters the cartridge through the emulated CART/FIRQ autostart path. A working
handoff adds `CARTRIDGE LOADED`, `CART ON`, and `CART ENTRY C000`; subsequent
PC snapshots help distinguish a running cartridge from a tight polling loop
or failed entry. `K`
shows whether the PS/2 decoder sees any matrix key, while `R` and `C` show the
last PIA keyboard row read and column-select write.

The logger only observes existing debug signals and does not stall the CPU.
`S` is the live SD-manager status byte. The complete status and detail bytes
remain available to CoCo software at `$FF60` and `$FF61`. Card removal stops
cache writeback; reinsertion remounts FAT32 and refreshes the browser without
reloading the bitstream.
`PC` comes from the MC6809's existing `RegData` output. It is the CPU's
current program-counter register and may point past an instruction being
executed; it is not an instruction trace or an arbitrary bus address.

This console is enabled in `COCO3_ELITE`. It is not DriveWire, a ROM console,
or an emulated CoCo RS-232 PAK; PC input is not consumed. Messages can be
coalesced while transmission is busy, so this is not a complete instruction trace.
