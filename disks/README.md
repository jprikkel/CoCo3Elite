# Disk images

This directory contains disk images selected for CoCo disk-controller testing.
`INTRUDERS.DSK` is mounted read-only as drive 0 and `DAGGORAT.DSK` is mounted
read-only as drive 1.

The initial controller accepts raw 161,280-byte, 35-track Disk BASIC images and
exposes them read-only from FPGA block RAM. Later milestones will read
selectable images from the Wukong Micro SD card.
