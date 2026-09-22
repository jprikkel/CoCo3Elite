# CoCo 3 Complete Price Comparison

Prices are in **U.S. dollars**, before shipping, taxes, and installation labor. The stock CoCo 3 estimate assumes a tested working machine with its original keyboard and power supply.

## Complete Upgrade Table

| # | Feature or upgrade | Stock CoCo 3 | Fully equipped CoCo 3 | Estimated added cost | Relevant product or information |
|---:|---|---|---|---:|---|
| 1 | Video output | Composite and analog RGB | GIME-Z digital video/DV output with HDMI-style connector; composite retained where practical | **+$115** | [GIME-Z and CoCo video hardware](https://www.cocopedia.com/wiki/index.php?title=Hardware#Video_Out) |
| 2 | SD-card storage | None | CoCo SDC floppy-drive emulator with case | **+$85** | [CoCo SDC — $85 complete, $65 PCB](https://thezippsterzone.com/2020/06/25/the-coco-sdc/) |
| 3 | Joystick support | Standard CoCo analog joystick ports | CoCo analog ports plus Atari-compatible joystick adapter | **+$15–$50** | [CoCo joystick and hardware information](https://www.cocopedia.com/wiki/index.php?title=Hardware) |
| 4 | Memory | 128 KB stock | 2 MB through the GIME-Z configuration | Included with selected GIME-Z setup | [GIME replacement and enhanced-memory information](https://thezippsterzone.com/author/zippster278/page/3/) |
| 5 | External keyboard | Original internal membrane keyboard | PS/2 keyboard interface | **+$40–$75** | [CoCo keyboard and interface hardware](https://www.cocopedia.com/wiki/index.php?title=Hardware) |
| 6 | Mechanical keyboard | Original membrane keyboard | CoCoMECH drop-in mechanical keyboard | **+$125** | [CoCoMECH keyboard](https://thezippsterzone.com/keyboards/) |
| 7 | Ethernet/Wi-Fi | None | Serial Wi-Fi module, normally ESP8266/ESP32-based; Ethernet would be a separate custom project | **+$15–$40** | [CoCo serial and ESP8266 Wi-Fi project](https://subethasoftware.com/2018/02/06/coco-rs-232-pak-to-3-wire-tx-rx-and-gnd-rs-232-device/) |
| 8 | RS-232 interface | No UART-based RS-232 Pak | Original CoCo RS-232 Pak or equivalent, DB-25 cable, adapters, and modern TTL/USB interface | **+$100–$200** | [CoCo RS-232 Pak and modern serial connections](https://subethasoftware.com/2018/02/06/coco-rs-232-pak-to-3-wire-tx-rx-and-gnd-rs-232-device/) |
| 9 | RS-232 cable pack | None | DB-25 cable, DB-25-to-DB-9 adapter, USB-RS-232 or RS-232-to-TTL adapter, and null-modem parts as needed | **+$20–$60** | [Serial cable and adapter examples](https://www.cdw.com/category/cables/cables-connectors/serial-cables/?w=BC6) |
| 10 | Speech/Sound Cartridge | None | Original Tandy Speech/Sound Cartridge, model 26-3144A | **+$75–$175 used** | [Speech/Sound Cartridge 26-3144A](https://www.cocopedia.com/wiki/Speech/Sound_Cartridge_(26-3144A)) |
| 11 | Speech/Sound high-speed modification | Not applicable | Modification allowing improved operation when the CoCo 3 runs above normal speed | **+$20–$75** | [CoCo hardware modifications](https://www.cocopedia.com/wiki/index.php?title=Hardware#Mods_%26_Hacking) |
| 12 | SID sound interface | No SID hardware | Custom CoCo 3 SID cartridge/interface board | **+$75–$175** | [CoCo hardware project directory](https://www.cocopedia.com/wiki/index.php?title=Hardware) |
| 13 | Actual SID chip | None | MOS 6581, MOS 8580, or a modern SID replacement | **+$30–$150** | [C64 SID technical information](https://www.c64-wiki.com/wiki/SID) |
| 14 | Multi-Pak Interface | None | Multi-slot cartridge interface for using SDC, RS-232, Speech/Sound, SID, and other cartridges together | **+$75–$140** | [Mini-MPI and MEGA-mini MPI](https://thezippsterzone.com/mpis-coco-sdc-etc/) |
| 15 | CoCo 2 extended-color video | Not applicable to the CoCo 3 build | Optional CoCo 2-only video project such as CoCoVGA, CocoDV, or RGBtoHDMI | **+$95–$150** | [CoCo video hardware](https://www.cocopedia.com/wiki/index.php?title=Hardware#Video_Out) |

## Price Totals

| Configuration | Included hardware | Estimated total |
|---|---|---:|
| Stock CoCo 3 | Tested CoCo 3, original keyboard, composite output, 128 KB RAM | **$200–$350** |
| Modernized CoCo 3 | Stock machine, GIME-Z, 2 MB RAM, SD storage, PS/2 support, Wi-Fi, Atari adapter, and mechanical keyboard | **$575–$760** |
| Modernized plus complete RS-232 | Previous configuration plus RS-232 Pak, cables, adapters, and serial accessories | **$695–$1,020** |
| Modernized plus Speech/Sound | Previous configuration plus 26-3144A cartridge and high-speed modification | **$790–$1,270** |
| Fully decked-out audio/serial system | Previous configuration plus Multi-Pak, SID interface, and SID chip | **$1,000–$1,800** |
| Fully built and tested | Hardware above plus repair, installation, testing, and custom wiring | **Approximately $1,200–$2,000** |

## Recommended Final Configuration

- Tested CoCo 3 donor machine
- GIME-Z with 2 MB RAM and digital video
- CoCo SDC with case
- Multi-Pak Interface
- Atari joystick adapter
- PS/2 keyboard interface
- CoCoMECH mechanical keyboard
- RS-232 Pak
- DB-25 serial cable and adapters
- RS-232-to-TTL interface
- ESP8266 or ESP32 Wi-Fi module
- Speech/Sound Cartridge 26-3144A
- High-speed Speech/Sound modification
- Custom SID cartridge interface
- Socketed MOS 6581, MOS 8580, or compatible SID replacement

## Technical Notes

### RS-232

A complete RS-232 setup should include:

- CoCo RS-232 Program Pak
- DB-25 serial cable
- DB-25-to-DB-9 adapter
- Null-modem adapter or cable where required
- USB-to-RS-232 adapter for modern computers
- Optional RS-232-to-TTL converter
- Optional ESP8266 or ESP32 Wi-Fi module

### Speech/Sound Cartridge

The original 26-3144A Speech/Sound Cartridge combines:

- AY-3-8913 programmable sound generator
- SPO256-AL2 speech processor
- Cartridge RAM

A high-speed modification may be needed when operating the CoCo 3 above its normal clock speed.

### SID Interface

A true C64 SID adapter should ideally support both the 6581 and 8580. The interface should include:

- CoCo cartridge-bus address decoding
- Data-bus buffering or level translation
- SID chip-select and read/write logic
- SID-compatible clock generation
- Selectable 9 V or 12 V SID supply
- SID-specific filter capacitors
- Audio mixing and output circuitry
- Optional SID paddle-input support
- Socketed SID chip

The 6581 and 8580 use different supply voltages and filter components, so they should not be treated as electrically identical.

### Multi-Pak

A Multi-Pak Interface is strongly recommended for the full configuration. Without one, the SDC, RS-232, Speech/Sound, SID, and other cartridges would compete for the CoCo 3’s single cartridge slot.

## Bottom Line

A stock, working CoCo 3 should cost approximately **$200–$350**.

A modernized CoCo 3 with GIME-Z, 2 MB RAM, SD storage, digital video, a mechanical keyboard, PS/2 support, Wi-Fi, RS-232, Speech/Sound, Multi-Pak, and SID hardware will likely cost:

> **$1,000–$1,800 in hardware**

A professionally assembled, repaired, wired, and tested system may reach:

> **$1,200–$2,000 total**
s
