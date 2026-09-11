# CoCo 3 Elite - A Modern Color Computer 3 Compatible

CoCo 3 Elite is a recreation of the classic Tandy Color Computer 3 with modern features such as HDMI video, SD-card storage, Atari Joystick Ports, modern keyboards, and USB support. While original software, games, music, and disk images run with minimal issues. Original peripherals such as Cartridges, Cassette, Joysticks, Serial/RS232 Devices, and Floppy Drives can be supported natively. 

The hardware-verified build boots a 128 KiB CoCo 3 system
ROM and displays Disk Extended Color BASIC over the board's HDMI
connector with 48 kHz stereo HDMI packets carrying the CoCo's mono DAC output.

*Note: The CoCo 3 Elite project is not endorsed or associated with Tandy(TM) or Radio Shack(TM)

![Extended Color BASIC running on the QMTECH Wukong V3](docs/images/wukong-coco3-basic.png)

CoCo3Elite is currently based on the AMD/Xilinx Vivado FPGA Artix-7 QMTECH Wukong V3 board. Hardware peripherals are primarily supported via standard PMOD adapters and can be mixed and matched to support the desired physical hardware. The current port targets the Wukong V3 fitted with an Artix-7 `XC7A100T` in
the FGG676 package. 

## Repository layout

```text
CoCo3Elite/
|-- rtl/              Verilog and VHDL sources
|   |-- core/         Portable CoCo memory, ROM, and boot-machine modules
|   |-- third-party/  Licensed upstream CPU, CoCo, peripheral, and HDMI RTL
|   `-- wukong/       Wukong top level, clocking, HDMI, and system integration
|-- constraints/      Board-specific XDC constraints
|-- scripts/          Vivado build, ROM preparation, and simulation scripts
|-- ip/               Vivado-generated IP
|-- tb/               Testbench sources
|-- build/            Generated ROM images, reports, checkpoints, and bitstreams
|-- roms/             User-supplied ROM inputs; ROM binaries are ignored by Git
|-- hardware/         Wukong interface pinouts and external wiring guides
`-- docs/              Porting notes, bring-up results, and board documentation
```

Generated content under `build/` is not committed.

Hardware interface documentation is maintained under [`hardware/`](hardware/):

- [QMTECH Wukong V3 board overview](hardware/wukong-board.md)
- [Wukong V3 PMOD pinout](hardware/wukong-pmod-pinout.md)
- [PS/2 keyboard interface](hardware/keyboard-ps2.md)
- [USB host prototype and proposed wiring](hardware/usb-host-interface.md)



The onboard USB connection is a passive UART diagnostic link

The [SD-card and USB support plan](docs/SDCARD_SUPPORT_PLAN.md) describes the
proposed filesystem browser, writable DSK images, cartridge/BAS/BIN loading,
FPGA management processor, and USB storage/input expansion.


## Documentation and references

- [Current Wukong implementation and known issues](docs/CURRENT_IMPLEMENTATION.md)
- [Wukong port notes](docs/WUKONG_PORT.md)
- [Hardware bring-up record](docs/BRINGUP.md)
- [Original CoCo3FPGA project](https://github.com/richard42/CoCo3FPGA)
- [RetroBIOS Tandy CoCo ROM collection](https://github.com/Abdess/retrobios/tree/main/bios/Tandy/CoCo)

See [LICENSE](LICENSE) for the source-code license. Third party libraries may have other licenses and ROM images may have separate
terms and are intentionally not distributed by this repository.



The current build names are `COCO3_ELITE`, `HDMI_TEST_PATTERN`, and
`BASIC_6809_DVI_TEST`. The last image is hardware-verified and displays
`CPU09`, `RESET VECTOR PASSED`, and `STAGE 2 RUNNING` in green on black.
