# hdl-util/hdmi vendored source

This directory contains source files from
[hdl-util/hdmi](https://github.com/hdl-util/hdmi), pinned at upstream commit
`83b1c9543a91b776671a44e68e130f81cae437b7`.

The upstream project implements HDMI 1.4b video and L-PCM audio output in
SystemVerilog. It is dual-licensed under MIT or Apache License 2.0; both license
texts and the upstream README are retained in this directory.

CoCo3FPGA initially compiles the module with `DVI_OUTPUT=1` to verify video and
serialization independently. A later checkpoint will enable true HDMI data
islands and connect CoCo audio samples.

Vendored source files are kept unchanged from the pinned upstream commit.
Board-specific integration and adaptation belong outside this directory.
