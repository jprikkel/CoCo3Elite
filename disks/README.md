# Disk images

This directory contains disk images supplied for CoCo disk-controller testing.
`CASHMAN.DSK` is the first read-only integration target. `512KTEST.DSK` is
reserved for later memory and disk compatibility testing.

Both current images are 161,280-byte, 35-track Disk BASIC images. The initial
controller milestone will expose `CASHMAN.DSK` as drive 0 from FPGA block RAM;
later milestones will read selectable images from the Wukong Micro SD card.
