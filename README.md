# CoCo 3 Elite - A Modern Color Computer 3 Compatible

CoCo 3 Elite is a recreation of the classic Tandy Color Computer 3 with modern features such as HDMI video, SD-card storage, Atari joystick ports, and modern keyboards. Original software, games, music, disk images, and cartridge images can run on the recreated system. Additional original and modern peripherals are planned.

The hardware-verified build boots a 128 KiB Color Computer 3 system
ROM and displays Disk Extended Color BASIC over the board's HDMI
connector with 48 kHz stereo HDMI packets carrying the mono DAC output.

*Note: The CoCo 3 Elite project is not endorsed by or associated with Tandy(TM) or Radio Shack(TM)

![Extended Color BASIC running on the QMTECH Wukong V3](docs/images/wukong-coco3-basic.png)

CoCo3Elite is currently based on the QMTECH Wukong V3 Artix-7 FPGA board. Hardware peripherals are primarily supported via standard PMOD adapters and can be mixed and matched to support the desired physical hardware. The current port targets the Wukong V3 fitted with an Artix-7 `XC7A100T` in
the FGG676 package. AMD/Xilinx Vivado software is used to build the system.

## Repository layout

```text
CoCo3Elite/
|-- constraints/      Board-specific XDC constraints
|-- rtl/              Verilog and VHDL sources
|   |-- core/         Portable CoCo memory, ROM, and boot-machine modules
|   |-- wukong/       Wukong-specific top level, clocking, HDMI, and integration
|   `-- third-party/  Separately licensed CPU, CoCo, peripheral, and HDMI RTL
|       |-- MC6809/              Cycle Accurate MC6809 HDL
|       |-- PS2_Key/             CoCo3FPGA PS2 Keyboard HDL
|       |-- SPI/                 CoCo3FPGA SPI support, not used
|       |-- UART_6551/           Potential full RS232 support via 6551 cartridge emulation
|       |-- coco3fpga/           CoCo3FPGA GIME, Video, Sound support HDL
|       |-- hdl-util-hdmi/       Common HDMI Video and Audio support (not DVI)
|       `-- ultraembedded-riscv  RISC-V management CPU used for SD-card services
|-- scripts/          Vivado build, ROM preparation, and simulation scripts
|-- tb/               Testbench sources
|-- build/            Generated ROM images, reports, checkpoints, and bitstreams, not committed
|-- roms/             User-supplied ROM inputs; ROM binaries are ignored by Git
|-- hardware/         Hardware interface pinouts and external wiring guides
`-- docs/             Porting notes, bring-up results, and board documentation
```

Hardware interface documentation is maintained under [`hardware/`](hardware/):

- [QMTECH Wukong V3 board overview](hardware/wukong-board.md)
- [Wukong V3 PMOD pinout](hardware/wukong-pmod-pinout.md)
- [PS/2 keyboard interface](hardware/pmod-keyboard-ps2-interface.md)
- [USB host prototype and proposed wiring](hardware/pmod-usb-host-interface.md)

The onboard USB connection is a passive UART diagnostic link.

The [SD-card and USB support plan](docs/SDCARD_SUPPORT_PLAN.md) describes the
implemented FAT32 browser, writable DSK images and cartridge loading, plus
planned BAS/BIN loading and USB storage/input expansion.

## Documentation and references

- [Current Wukong implementation and known issues](docs/CURRENT_IMPLEMENTATION.md)
- [Direct BIN and cartridge expansion plans](docs/BIN_FILE.md)
- [Wukong port notes](docs/WUKONG_PORT.md)
- [Hardware bring-up record](docs/BRINGUP.md)
- [Original CoCo3FPGA project](https://github.com/richard42/CoCo3FPGA)
- [RetroBIOS Tandy CoCo ROM collection](https://github.com/Abdess/retrobios/tree/main/bios/Tandy/CoCo)

See [LICENSE](LICENSE) for the project source-code license and
[LICENSES](LICENSES) for retained notices covering incorporated code.
Third-party libraries may have other licenses, and ROM images may have
separate terms and are intentionally not distributed by this repository.

The current build names are `COCO3_ELITE`, `HDMI_TEST_PATTERN`, and
`BASIC_6809_DVI_TEST`. The last image is hardware-verified and displays
`CPU09`, `RESET VECTOR PASSED`, and `STAGE 2 RUNNING` in green on black.
