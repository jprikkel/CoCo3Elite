# Quartus / DE1 project

This flat directory contains the original Intel/Altera Quartus project and its
vendor-specific generated IP:

- `CoCo3FPGA.qpf` and `coco3fpga_dw.qsf`: project and revision settings
- `*.qip`: generated-IP file manifests
- `*.mif`: initialized memory contents
- generated Verilog wrappers for `altsyncram`, `dcfifo`, and
  `cycloneii_clkctrl`

Portable handwritten HDL remains in `../rtl`; the QSF references it there.
Open `CoCo3FPGA.qpf` from this directory when using Quartus. The Vivado Wukong
build does not read anything from this directory.

The historical QSF references several files absent from the source repository,
including `disk_c0.*`, `disk_c8.qip`, `disk_d0.qip`, `disk_d8.qip`,
`buffer_dp.mif`, `disk02_1.qip`, `Video_DAC.qip`, and `uartclk.qip`. Their
absence predates this reorganization.
