# CoCo3Elite USB serial diagnostics

The Wukong V3 onboard CH340N USB-to-UART bridge provides a passive debug
console for the CoCo 3 implementation. The FPGA transmits on package pin E3;
the bridge's receive path on F3 is intentionally unused for now.

Connect the board's Mini-USB serial connector and open its Windows COM port at
**115200 baud, 8 data bits, no parity, 1 stop bit, no flow control**. For COM3:

```powershell
.\tools\putty\putty.exe -serial COM3 -sercfg 115200,8,n,1,N
```

The console reports `COCO3 UART READY`, cartridge enable/entry events, and a
once-per-second opcode-fetch address plus keyboard state such as:

```text
PC=A176 K=0 R=FF C=FF
```

Press F3 to present the
[ZIA cocodiag cartridge](https://github.com/varmfskii/cocodiag) to the running
CoCo. The system ROM enters it through the emulated CART/FIRQ autostart path;
F3 does not reset the CPU or replace its reset vector. A working handoff adds
`CART ON` and `CART ENTRY C000`; subsequent PC snapshots help distinguish a
running diagnostic from a tight polling loop or failed cartridge entry. `K`
shows whether the PS/2 decoder sees any matrix key, while `R` and `C` show the
last PIA keyboard row read and column-select write.

The logger only observes existing debug signals and does not stall the CPU.
`PC` is retained from the most recent CPU opcode fetch, rather than sampled
from an arbitrary RAM or I/O bus cycle.

This console is enabled in `COCO3_ELITE`. It is not DriveWire, a ROM console,
or an emulated CoCo RS-232 PAK; PC input is not consumed. Messages can be
coalesced while transmission is busy, so this is not a complete instruction trace.
