# CoCo 3 Elite management settings UI

The management UI is a 64×30 character OSD opened with **F12**, with a two-pane layout: the left pane is the category tree and the right pane shows editable values for the selected category.

```text
╔══════════════════════════════════════════════════════════════╗
║              C O C O  3  E L I T E   SETTINGS      [F12]    ║
╠═══════════════╤══════════════════════════════════════════════╣
│ > Audio       │ AUDIO                          │
│   Video       │ Volume                 80%     │
│   Joystick    │ Simulated disk sounds   ON      │
│   Cassette    │ Cassette tape playthru  OFF     │
│   Floppy      │ Future audio chips     AUTO     │
│   Cartridge   │                                │
│   Serial      │                                │
│   Ethernet    │                                │
╟───────────────┴──────────────────────────────────────────────╢
║ QUICK ACTIONS:  SOFT POWER   HARD RESET   REBOOT             ║
║ LEFT/RIGHT CATEGORY  UP/DOWN OPTION  ENTER SELECT           ║
╚══════════════════════════════════════════════════════════════╝
```

## Settings tree

- Audio: Volume, Simulated disk sounds, Cassette tape playthru, Future hardware audio chips
- Video: Resolution, Scaling, Color artifacting, Status overlays, CRT filter
- Joystick: Keyboard emulation, Swap joystick keys, Cycle joystick, Hardware source, Autofire, Autofire rate, Atari hardware, Classic analog
- Cassette: Motor, Input source, Monitor/playthru, Relay polarity, Auto rewind
- Floppy: Drive 0/1/2 source, Write protect, Disk sounds, Double density, Fast motor
- Cartridge: Cartridge image, Auto-launch, Cold reset on insert, Cartridge ROM wait states
- Serial: Port mode, Baud rate, RX/TX routing, RTS/CTS, Invert signals
- Ethernet: Enable, DHCP, MAC address, IP address, Gateway, Core network service
- Quick Actions: Soft power, Hard reset, Reboot

Values are staged in RAM and committed together with **Apply**. **Cancel** discards the staged values. Options marked `future` render as unavailable until the matching RTL capability is present.

The wider/taller layout requires the OSD character RAM and compositor to expose at least 64 columns × 30 rows. Quick actions are momentary commands and are never persisted with settings; hard reset should display a confirmation prompt before asserting reset.
