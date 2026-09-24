`timescale 1ns/1ps
`default_nettype none
`ifdef WUKONG_HYBRID_512K
`ifndef WUKONG_BRAM_DISK
`define WUKONG_DISK_PREFETCH
`define WUKONG_SHARED_DISK_CACHE
`endif
`endif
`ifdef WUKONG_SDRAM
`define WUKONG_DISK_PREFETCH
`endif

// Project-owned AXI-Lite peripheral for the manager firmware smoke test.
// 0x80000000 UART byte write; 0x80000004 UART TX busy (bit 0).
// 0x80000008 UART RX byte/pop; 0x8000000c RX status/count.
// 0x80000100 SPI control: bit 0 CS_n, bits 15:8 half-period divider.
// 0x80000104 SPI transfer byte write (response is delayed until byte complete).
// 0x80000108 SPI received byte read.  0x80000200..214 are the FDC mailbox and
// its 256-byte shared read buffer. OSD font style is at 0x80000278 and live
// artifact/CoCo 2 video settings are at 0x8000027c and the text-color theme
// is at 0x80000280. The
// delayed write response is intentional:
// it makes one MMIO store exactly one synchronous SPI byte transaction.
module manager_sd_mmio #(
    parameter integer UART_CLKS_PER_BIT = 434,
    parameter integer DISK_CACHE_BYTES = 161280
) (
    input wire clock, input wire memory_clock, input wire reset,
    input wire axi_awvalid, output wire axi_awready, input wire [31:0] axi_awaddr,
    input wire axi_wvalid, output wire axi_wready, input wire [31:0] axi_wdata,
    input wire [3:0] axi_wstrb, output reg axi_bvalid, input wire axi_bready,
    output wire [1:0] axi_bresp,
    input wire axi_arvalid, output wire axi_arready, input wire [31:0] axi_araddr,
    output reg axi_rvalid, input wire axi_rready, output reg [31:0] axi_rdata,
    output wire [1:0] axi_rresp,
    output wire uart_tx, output wire uart_busy_o, input wire uart_rx,
    output reg uart_claim,
    output reg sd_cs_n, output reg sd_sck, output reg sd_mosi,
    input wire sd_miso,
    input wire [1:0] fdc_drive, input wire fdc_side,
    input wire [7:0] fdc_track,
    input wire [7:0] fdc_sector, input wire [7:0] fdc_last_type1, input wire [31:0] fdc_debug_word, input wire [31:0] fdc_completed_debug_word, input wire fdc_read_complete_toggle, input wire fdc_write_complete_toggle, input wire fdc_request_toggle,
    input wire [7:0] fdc_buffer_address, output wire [7:0] fdc_buffer_data,
    input wire fdc_write_strobe, input wire [7:0] fdc_write_data,
    input wire [9:0] menu_key_state,
    input wire [10:0] osd_char_address,
    output wire [7:0] osd_char_data,
    input wire [11:0] osd_preview_read_address,
    output reg [31:0] osd_preview_read_data,
    output reg osd_preview_active,
    output reg [127:0] osd_preview_palette,
    output reg osd_active,
    output reg [4:0] osd_selected_row,
    output reg osd_narrow_selection,
    output reg osd_option_selection,
    output reg [1:0] osd_font_style,
    output reg [2:0] artifact_mode,
    output reg [1:0] artifact_palette,
    output reg [3:0] coco2_palette,
    output reg [3:0] text_color_theme,
    output reg [55:0] serial_keyboard_keys,
    output reg serial_keyboard_shift, output reg serial_keyboard_shift_override,
    output reg [7:0] serial_function_keys,
    output reg serial_cold_reset,
    output reg serial_trace_enable,
    output reg serial_trace_snapshot_toggle,
    input wire [15:0] debug_cpu_pc,
    input wire [7:0] debug_gime_init0, input wire [7:0] debug_gime_init1,
    input wire [7:0] debug_video_mode, input wire [7:0] debug_video_resolution,
    input wire physical_floppy_present,
    input wire [2:0] physical_floppy_status,
    input wire [31:0] physical_floppy_index_count,
    input wire [31:0] physical_floppy_read_transition_count,
    output reg physical_floppy_motor_request,
    output reg physical_floppy_direction_request,
    output reg physical_floppy_side_select_request,
    output reg physical_floppy_step_request_toggle,
    output reg physical_floppy_home_request_toggle,
    output reg physical_floppy_abort_request_toggle,
    input wire physical_floppy_motor_active,
    input wire physical_floppy_home_active,
    input wire physical_floppy_home_done_toggle,
    input wire physical_floppy_home_success,
    input wire [7:0] physical_floppy_home_step_count,
    output reg video_capture_request_toggle,
    output reg [2:0] video_capture_stripe,
    output reg [15:0] video_capture_read_address,
    input wire [7:0] video_capture_read_data,
    input wire video_capture_done_toggle, input wire video_capture_busy,
    output reg fdc_done_toggle, output reg fdc_success,
    output reg fdc_write_done_toggle, output reg fdc_write_success,
    output reg [2:0] fdc_present, output reg manager_ready
    ,output reg [14:0] cartridge_address, output reg [7:0] cartridge_data,
    output reg cartridge_write, output reg cartridge_enabled, output reg cartridge_launch,
    input wire bin_fifo_pop, input wire bin_loader_done, input wire bin_cancel,
    output wire [7:0] bin_fifo_data, output wire bin_fifo_available,
    output reg bin_transfer_active, output reg bin_transfer_complete,
    output reg bin_transfer_error,
    output wire shared_disk_write,
    output wire [19:0] shared_disk_write_address,
    output wire [7:0] shared_disk_write_data,
    input wire shared_disk_write_ready,
    input wire shared_disk_write_idle,
    output wire shared_disk_sector_request_toggle,
    output wire [19:0] shared_disk_sector_base_address,
    input wire [7:0] shared_disk_sector_read_data,
    input wire shared_disk_sector_done_toggle,
    input wire shared_disk_ready,
    output wire sdram_clk, output wire sdram_cke,
    output wire sdram_cs_n, output wire sdram_ras_n,
    output wire sdram_cas_n, output wire sdram_we_n,
    output wire [1:0] sdram_dqm,
    output wire [12:0] sdram_address,
    output wire [1:0] sdram_bank,
    inout wire [15:0] sdram_data
);
    localparam UART_DATA = 32'h80000000, UART_STATUS = 32'h80000004,
               UART_RX_DATA = 32'h80000008, UART_RX_STATUS = 32'h8000000c,
               SPI_CTRL = 32'h80000100, SPI_XFER = 32'h80000104,
               SPI_DATA = 32'h80000108, FDC_STATE = 32'h80000200,
               FDC_INFO = 32'h80000204, FDC_BUFFER_RESET = 32'h80000208,
               FDC_BUFFER_DATA = 32'h8000020c, FDC_ACK = 32'h80000210,
               MOUNT_STATUS = 32'h80000214, FDC_BUFFER_PEEK = 32'h80000218, FDC_DEBUG_WORD = 32'h8000021c,
               FDC_BUFFER_DEBUG_ADDRESS = 32'h80000220, FDC_BUFFER_DEBUG_DATA = 32'h80000224, FDC_COMPLETED_DEBUG_WORD = 32'h80000228, FDC_WRITE_ACK = 32'h8000022c,
               DISK_CACHE_RESET = 32'h80000230, DISK_CACHE_DATA = 32'h80000234, DISK_CACHE_COMMIT = 32'h80000238, DISK_CACHE_STATUS = 32'h8000023c,
               FDC_WRITE_BUFFER_DEBUG_DATA = 32'h80000240,
               DISK_CACHE_DEBUG_ADDRESS = 32'h80000244,
               DISK_CACHE_DEBUG_DATA = 32'h80000248,
               OSD_ADDRESS = 32'h8000024c,
               OSD_DATA = 32'h80000250,
               OSD_CONTROL = 32'h80000254,
               MENU_KEY_STATE = 32'h80000258,
               CARTRIDGE_ADDRESS = 32'h8000025c, CARTRIDGE_DATA = 32'h80000260,
               CARTRIDGE_CONTROL = 32'h80000264,
               CARTRIDGE_SIGNATURE = 32'h80000268,
               BIN_FIFO_DATA = 32'h8000026c,
               BIN_FIFO_CONTROL = 32'h80000270,
               BIN_FIFO_STATUS = 32'h80000274,
               OSD_FONT_STYLE = 32'h80000278,
               VIDEO_SETTINGS = 32'h8000027c,
               TEXT_SETTINGS = 32'h80000280,
               SERIAL_KEY_LO = 32'h80000284,
               SERIAL_KEY_HI = 32'h80000288,
               SERIAL_KEY_CONTROL = 32'h8000028c,
               SERIAL_FUNCTION_KEYS = 32'h80000290,
               SERIAL_MACHINE_CONTROL = 32'h80000294,
               DEBUG_CPU_STATUS = 32'h80000298,
               DEBUG_VIDEO_STATUS = 32'h8000029c,
               UART_CONTROL = 32'h800002a0,
               VIDEO_CAPTURE_CONTROL = 32'h800002a4,
               VIDEO_CAPTURE_STATUS = 32'h800002a8,
               VIDEO_CAPTURE_ADDRESS = 32'h800002ac,
               VIDEO_CAPTURE_DATA = 32'h800002b0,
               OSD_PREVIEW_ADDRESS = 32'h800002b4,
               OSD_PREVIEW_DATA = 32'h800002b8,
               OSD_PREVIEW_PALETTE = 32'h800002bc,
               OSD_PREVIEW_CONTROL = 32'h800002c0,
               PHYSICAL_FLOPPY_STATUS = 32'h800002c4,
               PHYSICAL_FLOPPY_INDEX_COUNT = 32'h800002c8,
               PHYSICAL_FLOPPY_READ_COUNT = 32'h800002cc,
               PHYSICAL_FLOPPY_CONTROL = 32'h800002d0;
    reg have_address, have_data, transaction_active, await_spi, spi_seen_busy;
    reg [31:0] write_address, write_data;
    reg [7:0] spi_tx, spi_rx, spi_tx_shift, spi_rx_shift;
    reg [7:0] spi_divider, spi_divider_count;
    reg [3:0] spi_bit_count;
    reg spi_busy, spi_start;
    reg [7:0] uart_data;
    reg uart_start;
    wire [7:0] uart_rx_data;
    wire uart_rx_valid, uart_rx_framing_error;
    (* ram_style = "distributed" *) reg [7:0] uart_rx_fifo [0:15];
    reg [3:0] uart_rx_write_pointer, uart_rx_read_pointer;
    reg [4:0] uart_rx_count;
    reg uart_rx_overflow, uart_rx_frame_seen;
    // The manager firmware compares this rolling signature after every raw
    // cartridge load.  It covers both byte values and their target addresses,
    // catching a dropped, repeated, or misaddressed MMIO write before the
    // 6809 is allowed to execute the image.
    reg [31:0] cartridge_signature;
    // Small producer/consumer FIFO between RV32 file transports and the 6809
    // loader.  Keeping this interface transport-neutral lets later serial and
    // Ethernet services reuse the exact DECB parser and CoCo launch path.
    (* ram_style = "distributed" *) reg [7:0] bin_fifo [0:15];
    reg [3:0] bin_fifo_write_pointer, bin_fifo_read_pointer;
    reg [4:0] bin_fifo_count;
    reg bin_loader_done_seen, bin_cancelled;
    (* ram_style = "distributed" *) reg [7:0] osd_chars [0:2047];
    reg [10:0] osd_write_address;
    // The browser preview is a fixed 184x138, 4-bpp 4:3 surface. Eight pixels
    // are packed into each 32-bit word, consuming 12.4 KiB of block RAM.
    // The manager and HDMI OSD use the same pixel clock, so one synchronous
    // read port is deterministic and needs no clock-domain crossing.
    (* ram_style = "block" *) reg [31:0] osd_preview_words [0:3173];
    reg [11:0] osd_preview_write_address;
    // These banks require asynchronous reads at the CoCo bus service edge.
    // Force LUT RAM so implementation cannot silently turn the FDC-facing
    // port into a clocked block-RAM read and retain the preceding sector.
    (* ram_style = "distributed" *) reg [7:0] fdc_buffer0 [0:255];
    (* ram_style = "distributed" *) reg [7:0] fdc_buffer1 [0:255];
    reg [7:0] fdc_write_buffer [0:255];
    reg [7:0] fdc_buffer_write_address, fdc_buffer_debug_address;
    reg [8:0] fdc_buffer_fill_count;
    reg [1:0] fdc_ack_delay;
    reg fdc_ack_pending, fdc_ack_success_pending, fdc_ack_toggle_pending;
    reg fdc_buffer_read_bank, fdc_buffer_write_bank;
    // Drive 0 is loaded as a complete image. The active build keeps it in a
    // separate SDRAM region from upper CoCo RAM under one shared controller.
    // The two small sector banks above are reserved for later drive 1/2
    // demand paging and are never selected for a mounted drive 0.
    reg [19:0] disk_cache_write_address;
    reg [19:0] disk_cache_debug_address;
    reg [19:0] disk_cache_image_bytes;
    reg disk_cache_ready;
    wire [7:0] disk_cache_fdc_data;
    reg disk_sector_request_toggle;
    reg [19:0] disk_sector_base_address;
    reg disk_sector_ack_wait;
    wire disk_sector_done_toggle;
    reg [1:0] disk_sector_done_sync;
    wire disk_sdram_ready;
    wire [31:0] disk_sdram_debug_status;
    wire disk_double_sided = disk_cache_image_bytes == 20'd368640;
    wire [7:0] disk_track_count = disk_double_sided ? 8'd40 : 8'd35;
    wire [11:0] disk_track_sector_base = disk_double_sided
        ? ({4'b0, fdc_track} << 5) + ({4'b0, fdc_track} << 2)
        : ({4'b0, fdc_track} << 4) + ({4'b0, fdc_track} << 1);
    wire [11:0] disk_cache_linear_sector = disk_track_sector_base +
        (disk_double_sided && fdc_side ? 12'd18 : 12'd0) +
        {4'b0, fdc_sector} - 12'd1;
    wire [19:0] disk_cache_fdc_address =
        {disk_cache_linear_sector, fdc_buffer_address};
    wire disk_cache_fdc_valid = disk_cache_ready && fdc_drive == 2'd0 &&
                                fdc_track < disk_track_count &&
                                (!fdc_side || disk_double_sided) &&
                                fdc_sector >= 8'd1 && fdc_sector <= 8'd18;
    wire uart_busy;
    assign uart_busy_o = uart_busy;
    // Firmware owns FAT32. The SDRAM controller fetches a whole sector before
    // acknowledging the FDC; its buffer uses the same one-clock read latency
    // as the original block-RAM disk cache.
    wire [7:0] sector_cache_data = fdc_buffer_read_bank
                                 ? fdc_buffer1[fdc_buffer_address]
                                 : fdc_buffer0[fdc_buffer_address];
    assign fdc_buffer_data = disk_cache_fdc_valid ? disk_cache_fdc_data
                                                  : sector_cache_data;
    assign osd_char_data = osd_chars[osd_char_address];
    assign bin_fifo_data = bin_fifo[bin_fifo_read_pointer];
    assign bin_fifo_available = bin_fifo_count != 0;
    wire bin_fifo_pop_now = bin_fifo_pop && bin_fifo_count != 0;

    assign axi_awready = !have_address && !transaction_active;
    assign axi_wready = !have_data && !transaction_active;
    assign axi_bresp = 2'b00;
    assign axi_arready = !axi_rvalid;
    assign axi_rresp = 2'b00;

`ifdef WUKONG_SHARED_DISK_CACHE
    wire disk_cache_accept_write = shared_disk_write_ready;
    wire disk_cache_commit_idle = shared_disk_write_idle;
`else
    wire disk_cache_accept_write = 1'b1;
    wire disk_cache_commit_idle = 1'b1;
`endif
    wire disk_cache_load_write = !reset && !transaction_active &&
                                 have_address && have_data &&
                                 write_address == DISK_CACHE_DATA &&
                                 disk_cache_write_address < DISK_CACHE_BYTES &&
                                 disk_cache_accept_write;
    wire disk_cache_fdc_write = fdc_write_strobe && disk_cache_fdc_valid;
    wire disk_cache_port_write = disk_cache_fdc_write || disk_cache_load_write;
    wire [19:0] disk_cache_port_write_address = disk_cache_fdc_write
                                                ? disk_cache_fdc_address
                                                : disk_cache_write_address;
    wire [7:0] disk_cache_port_write_data = disk_cache_fdc_write
                                           ? fdc_write_data : write_data[7:0];
    // Firmware may inspect the cache only before it marks the manager ready;
    // afterward port B belongs exclusively to the live FDC.
    wire [19:0] disk_cache_read_address = manager_ready
                                          ? disk_cache_fdc_address
                                          : disk_cache_debug_address;

`ifdef WUKONG_SHARED_DISK_CACHE
    assign shared_disk_write = disk_cache_port_write;
    assign shared_disk_write_address = disk_cache_port_write_address;
    assign shared_disk_write_data = disk_cache_port_write_data;
    assign shared_disk_sector_request_toggle = disk_sector_request_toggle;
    assign shared_disk_sector_base_address = disk_sector_base_address;
`else
    // BRAM owns disk 0. Do not send duplicate writes or sector requests to
    // the upper-RAM SDRAM controller; video/CPU retain its full bandwidth.
    assign shared_disk_write = 1'b0;
    assign shared_disk_write_address = 20'b0;
    assign shared_disk_write_data = 8'b0;
    assign shared_disk_sector_request_toggle = 1'b0;
    assign shared_disk_sector_base_address = 20'b0;
`endif

`ifdef WUKONG_SHARED_DISK_CACHE
    // Upper CoCo RAM and disk share the machine's single SDRAM controller.
    // The manager never drives a second set of external SDRAM pins.
    assign disk_cache_fdc_data = shared_disk_sector_read_data;
    assign disk_sector_done_toggle = shared_disk_sector_done_toggle;
    assign disk_sdram_ready = shared_disk_ready;
    assign disk_sdram_debug_status = 32'b0;
    assign sdram_clk = 1'b0;
    assign sdram_cke = 1'b0;
    assign sdram_cs_n = 1'b1;
    assign sdram_ras_n = 1'b1;
    assign sdram_cas_n = 1'b1;
    assign sdram_we_n = 1'b1;
    assign sdram_dqm = 2'b11;
    assign sdram_address = 13'b0;
    assign sdram_bank = 2'b0;
    assign sdram_data = 16'hzzzz;
`elsif WUKONG_SDRAM
    // Keep CoCo RAM/video on the proven dual-port BRAM.  SDRAM holds only the
    // mounted drive-0 image; a complete sector is prefetched before FDC_ACK.
    manager_sdram_disk_cache disk_cache_i (
        .memory_clock(memory_clock), .cache_clock(clock), .reset(reset),
        .cache_write(disk_cache_port_write),
        .cache_write_address(disk_cache_port_write_address[17:0]),
        .cache_write_data(disk_cache_port_write_data),
        .sector_request_toggle(disk_sector_request_toggle),
        .sector_base_address(disk_sector_base_address[17:0]),
        .sector_read_address(fdc_buffer_address),
        .sector_read_data(disk_cache_fdc_data),
        .sector_done_toggle(disk_sector_done_toggle),
        .ready(disk_sdram_ready), .debug_status(disk_sdram_debug_status),
        .sdram_clk(sdram_clk), .sdram_cke(sdram_cke),
        .sdram_cs_n(sdram_cs_n), .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n), .sdram_we_n(sdram_we_n),
        .sdram_dqm(sdram_dqm), .sdram_address(sdram_address),
        .sdram_bank(sdram_bank), .sdram_data(sdram_data)
    );
`else
    // An explicit primitive avoids synthesis-dependent inference for the
    // boot-loader/runtime-write address mux and guarantees that the 161 KB
    // image consumes block RAM with a one-clock FDC read latency.
    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(18),
        .ADDR_WIDTH_B(18),
        .BYTE_WRITE_WIDTH_A(8),
        .CASCADE_HEIGHT(1),
        .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(DISK_CACHE_BYTES * 8),
        .READ_DATA_WIDTH_B(8),
        .READ_LATENCY_B(1),
        .READ_RESET_VALUE_B("0"),
        .RST_MODE_B("SYNC"),
        .WRITE_DATA_WIDTH_A(8),
        .WRITE_MODE_B("read_first")
    ) disk_cache_i (
        .clka(clock), .clkb(clock),
        .ena(disk_cache_port_write), .wea(disk_cache_port_write),
        .addra(disk_cache_port_write_address[17:0]), .dina(disk_cache_port_write_data),
        .enb(1'b1), .addrb(disk_cache_read_address[17:0]),
        .doutb(disk_cache_fdc_data), .regceb(1'b1), .rstb(reset),
        .sleep(1'b0), .injectdbiterra(1'b0), .injectsbiterra(1'b0),
        .dbiterrb(), .sbiterrb()
    );
    assign disk_sector_done_toggle = disk_sector_request_toggle;
    assign disk_sdram_ready = 1'b1;
    assign disk_sdram_debug_status = 32'b0;
    assign sdram_clk = 1'b0;
    assign sdram_cke = 1'b0;
    assign sdram_cs_n = 1'b1;
    assign sdram_ras_n = 1'b1;
    assign sdram_cas_n = 1'b1;
    assign sdram_we_n = 1'b1;
    assign sdram_dqm = 2'b11;
    assign sdram_address = 13'b0;
    assign sdram_bank = 2'b0;
    assign sdram_data = 16'hzzzz;
`endif

    uart_tx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) uart_i (
        .clock(clock), .reset(reset), .data(uart_data), .start(uart_start),
        .tx(uart_tx), .busy(uart_busy)
    );

    uart_rx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) uart_rx_i (
        .clock(clock), .reset(reset), .rx(uart_rx), .data(uart_rx_data),
        .data_valid(uart_rx_valid), .framing_error(uart_rx_framing_error)
    );

    // Reading UART_RX_DATA consumes one byte.  A simultaneous receive and
    // consume keeps occupancy stable, allowing sustained full-duplex traffic.
    wire uart_rx_pop = axi_arvalid && axi_arready &&
                       axi_araddr == UART_RX_DATA && uart_rx_count != 0;
    wire uart_rx_push = uart_rx_valid && uart_rx_count != 5'd16;
    always @(posedge clock) begin
        if (reset) begin
            uart_rx_write_pointer <= 0;
            uart_rx_read_pointer <= 0;
            uart_rx_count <= 0;
            uart_rx_overflow <= 1'b0;
            uart_rx_frame_seen <= 1'b0;
        end else begin
            if (uart_rx_framing_error) uart_rx_frame_seen <= 1'b1;
            if (uart_rx_valid && uart_rx_count == 5'd16 && !uart_rx_pop)
                uart_rx_overflow <= 1'b1;
            if (uart_rx_push) begin
                uart_rx_fifo[uart_rx_write_pointer] <= uart_rx_data;
                uart_rx_write_pointer <= uart_rx_write_pointer + 1'b1;
            end
            if (uart_rx_pop)
                uart_rx_read_pointer <= uart_rx_read_pointer + 1'b1;
            case ({uart_rx_push, uart_rx_pop})
                2'b10: uart_rx_count <= uart_rx_count + 1'b1;
                2'b01: uart_rx_count <= uart_rx_count - 1'b1;
                default: uart_rx_count <= uart_rx_count;
            endcase
        end
    end

    // The FDC owns the write staging buffer.  Firmware reads it after the
    // complete 256-byte sector transfer and merges it into the FAT32 block.
    always @(posedge clock) begin
        if (fdc_write_strobe && fdc_present[0] && fdc_drive == 2'd0 &&
            fdc_track < disk_track_count &&
            (!fdc_side || disk_double_sided) &&
            fdc_sector >= 8'd1 && fdc_sector <= 8'd18) begin
            fdc_write_buffer[fdc_buffer_address] <= fdc_write_data;
        end
    end

    // Mode 0 SPI: sample MISO on rising edges; change MOSI on falling edges.
    always @(posedge clock) begin
        if (reset) begin
            sd_sck <= 1'b0;
            sd_mosi <= 1'b1;
            spi_busy <= 1'b0;
            spi_divider_count <= 0;
            spi_bit_count <= 0;
            spi_rx <= 8'hff;
            spi_tx_shift <= 8'hff;
            spi_rx_shift <= 0;
        end else if (spi_start && !spi_busy) begin
            spi_busy <= 1'b1;
            spi_divider_count <= 0;
            spi_bit_count <= 0;
            spi_tx_shift <= spi_tx;
            spi_rx_shift <= 0;
            sd_sck <= 1'b0;
            sd_mosi <= spi_tx[7];
        end else if (spi_busy) begin
            if (spi_divider_count == spi_divider - 1'b1) begin
                spi_divider_count <= 0;
                if (!sd_sck) begin
                    sd_sck <= 1'b1;
                    spi_rx_shift <= {spi_rx_shift[6:0], sd_miso};
                end else begin
                    sd_sck <= 1'b0;
                    if (spi_bit_count == 7) begin
                        spi_busy <= 1'b0;
                        spi_rx <= spi_rx_shift;
                        sd_mosi <= 1'b1;
                    end else begin
                        spi_bit_count <= spi_bit_count + 1'b1;
                        spi_tx_shift <= {spi_tx_shift[6:0], 1'b1};
                        sd_mosi <= spi_tx_shift[6];
                    end
                end
            end else spi_divider_count <= spi_divider_count + 1'b1;
        end
    end

    always @(posedge clock) begin
        if (reset) begin
            have_address <= 0; have_data <= 0; transaction_active <= 0;
            await_spi <= 0; spi_seen_busy <= 0; write_address <= 0; write_data <= 0;
            axi_bvalid <= 0; axi_rvalid <= 0; axi_rdata <= 0;
            sd_cs_n <= 1'b1; spi_divider <= 8'd64; spi_tx <= 8'hff;
            spi_start <= 0; uart_data <= 0; uart_start <= 0;
            fdc_buffer_write_address <= 0;
            fdc_buffer_debug_address <= 0;
            fdc_buffer_fill_count <= 0;
            fdc_ack_delay <= 0;
            fdc_ack_pending <= 0;
            fdc_ack_success_pending <= 0;
            fdc_ack_toggle_pending <= 0;
            fdc_buffer_read_bank <= 0;
            fdc_buffer_write_bank <= 1;
            disk_cache_write_address <= 0;
            disk_cache_debug_address <= 0;
            disk_cache_image_bytes <= 20'd161280;
            disk_cache_ready <= 1'b0;
            disk_sector_request_toggle <= 1'b0;
            disk_sector_base_address <= 0;
            disk_sector_ack_wait <= 1'b0;
            disk_sector_done_sync <= 2'b00;
            osd_write_address <= 0;
            osd_preview_write_address <= 0;
            osd_preview_read_data <= 0;
            osd_preview_active <= 1'b0;
            osd_preview_palette <= 128'b0;
            osd_active <= 1'b0;
            osd_selected_row <= 0;
            osd_narrow_selection <= 1'b0;
            osd_option_selection <= 1'b0;
            osd_font_style <= 2'd1;
            // Two pass keeps Thin's detail while closing isolated same-color
            // artifact gaps, and is the preferred power-on presentation.
            artifact_mode <= 3'd5;
            artifact_palette <= 2'd0;
            coco2_palette <= 4'd0;
            text_color_theme <= 4'd0;
            serial_keyboard_keys <= 56'b0;
            serial_keyboard_shift <= 1'b0;
            serial_keyboard_shift_override <= 1'b0;
            serial_function_keys <= 8'b0;
            serial_cold_reset <= 1'b0;
            serial_trace_enable <= 1'b0;
            serial_trace_snapshot_toggle <= 1'b0;
            physical_floppy_motor_request <= 1'b0;
            physical_floppy_direction_request <= 1'b1;
            physical_floppy_side_select_request <= 1'b1;
            physical_floppy_step_request_toggle <= 1'b0;
            physical_floppy_home_request_toggle <= 1'b0;
            physical_floppy_abort_request_toggle <= 1'b0;
            uart_claim <= 1'b0;
            video_capture_request_toggle <= 1'b0;
            video_capture_stripe <= 3'b0;
            video_capture_read_address <= 16'b0;
            fdc_done_toggle <= 0; fdc_success <= 0;
            fdc_write_done_toggle <= 0; fdc_write_success <= 0;
            fdc_present <= 0; manager_ready <= 0;
            cartridge_address <= 0; cartridge_data <= 0;
            cartridge_write <= 1'b0;
            cartridge_enabled <= 1'b0; cartridge_launch <= 1'b0;
            cartridge_signature <= 32'b0;
            bin_fifo_write_pointer <= 0;
            bin_fifo_read_pointer <= 0;
            bin_fifo_count <= 0;
            bin_loader_done_seen <= 1'b0;
            bin_cancelled <= 1'b0;
            bin_transfer_active <= 1'b0;
            bin_transfer_complete <= 1'b0;
            bin_transfer_error <= 1'b0;
        end else begin
            disk_sector_done_sync <= {disk_sector_done_sync[0],
                                      disk_sector_done_toggle};
            // Clock-enable the preview BRAM only while it can be visible.
            // This removes continuous BRAM address/data switching from normal
            // CoCo video operation after the menu has closed.
            if (osd_active && osd_preview_active)
                osd_preview_read_data <=
                    osd_preview_words[osd_preview_read_address];
            else
                osd_preview_read_data <= 32'b0;
            cartridge_write <= 1'b0;
            cartridge_launch <= 1'b0;
            serial_cold_reset <= 1'b0;
            // Registered block-RAM read matches the proven embedded/full-disk
            // timing. During a CoCo write, update the cached byte immediately;
            // firmware separately persists the staged sector to FAT32.
            spi_start <= 0;
            uart_start <= 0;
            if (bin_fifo_pop_now) begin
                bin_fifo_read_pointer <= bin_fifo_read_pointer + 1'b1;
                bin_fifo_count <= bin_fifo_count - 1'b1;
            end
            // Publish a filled sector only after the complete 256-byte MMIO
            // write stream has retired and the buffer has remained stable for
            // additional clocks.  This prevents the FDC from observing the
            // previous sector when firmware immediately follows the final
            // data store with FDC_ACK.
`ifdef WUKONG_DISK_PREFETCH
            // The firmware's FDC_ACK starts a 256-byte SDRAM prefetch.  Do
            // not release the WD1773 from busy until the sector buffer is
            // complete and stable in this clock domain.
            if (disk_sector_ack_wait &&
                disk_sector_done_sync[1] == disk_sector_request_toggle) begin
                disk_sector_ack_wait <= 1'b0;
                fdc_ack_delay <= 2'd2;
                fdc_ack_pending <= 1'b1;
            end
`endif
            if (fdc_ack_pending) begin
                if (fdc_ack_delay != 0) begin
                    fdc_ack_delay <= fdc_ack_delay - 1'b1;
                end else begin
                    fdc_success <= fdc_ack_success_pending;
                    fdc_done_toggle <= fdc_ack_toggle_pending;
                    if (fdc_ack_success_pending) begin
                        // Atomically publish the completed bank.  Firmware
                        // fills the other bank on the following request, so
                        // the FDC read port cannot retain or race stale data.
                        fdc_buffer_read_bank <= fdc_buffer_write_bank;
                        fdc_buffer_write_bank <= ~fdc_buffer_write_bank;
                    end
                    fdc_ack_pending <= 1'b0;
                end
            end
            if (axi_awvalid && axi_awready) begin
                have_address <= 1'b1;
                write_address <= axi_awaddr;
            end
            if (axi_wvalid && axi_wready) begin
                have_data <= 1'b1;
                write_data <= axi_wdata;
            end
            if (!transaction_active && have_address && have_data &&
                (write_address != DISK_CACHE_DATA || disk_cache_accept_write) &&
                (write_address != DISK_CACHE_COMMIT || disk_cache_commit_idle)) begin
                transaction_active <= 1'b1;
                if (write_address == UART_DATA) begin
                    if (!uart_busy) begin uart_data <= write_data[7:0]; uart_start <= 1'b1; end
                    axi_bvalid <= 1'b1;
                end else if (write_address == SPI_CTRL) begin
                    sd_cs_n <= write_data[0];
                    if (write_data[15:8] != 0) spi_divider <= write_data[15:8];
                    axi_bvalid <= 1'b1;
                end else if (write_address == SPI_XFER) begin
                    spi_tx <= write_data[7:0];
                    spi_start <= 1'b1;
                    await_spi <= 1'b1;
                    spi_seen_busy <= 1'b0;
                end else if (write_address == FDC_BUFFER_RESET) begin
                    fdc_buffer_write_address <= 0;
                    fdc_buffer_fill_count <= 0;
                    axi_bvalid <= 1'b1;
                end else if (write_address == FDC_BUFFER_DATA) begin
                    if (fdc_buffer_write_bank)
                        fdc_buffer1[fdc_buffer_write_address] <= write_data[7:0];
                    else
                        fdc_buffer0[fdc_buffer_write_address] <= write_data[7:0];
                    fdc_buffer_write_address <= fdc_buffer_write_address + 1'b1;
                    if (fdc_buffer_fill_count != 9'd256)
                        fdc_buffer_fill_count <= fdc_buffer_fill_count + 1'b1;
                    axi_bvalid <= 1'b1;
                end else if (write_address == FDC_BUFFER_DEBUG_ADDRESS) begin
                    fdc_buffer_debug_address <= write_data[7:0];
                    axi_bvalid <= 1'b1;
                end else if (write_address == DISK_CACHE_RESET) begin
                    disk_cache_write_address <= 0;
                    disk_cache_ready <= 1'b0;
                    disk_sector_ack_wait <= 1'b0;
                    axi_bvalid <= 1'b1;
                end else if (write_address == DISK_CACHE_DATA) begin
                    if (disk_cache_write_address < DISK_CACHE_BYTES) begin
                        disk_cache_write_address <= disk_cache_write_address + 1'b1;
                    end
                    axi_bvalid <= 1'b1;
                end else if (write_address == DISK_CACHE_COMMIT) begin
                    disk_cache_ready <=
                        (write_data[19:0] == 20'd1 ||
                         write_data[19:0] == DISK_CACHE_BYTES ||
                         write_data[19:0] == 20'd161280 ||
                         write_data[19:0] == 20'd368640) &&
                        disk_cache_write_address ==
                            (write_data[19:0] == 20'd1
                             ? DISK_CACHE_BYTES : write_data[19:0]) &&
                        disk_sdram_ready;
                    disk_cache_image_bytes <= write_data[19:0] == 20'd1
                        ? DISK_CACHE_BYTES : write_data[19:0];
                    axi_bvalid <= 1'b1;
                end else if (write_address == DISK_CACHE_DEBUG_ADDRESS) begin
                    disk_cache_debug_address <= write_data[19:0];
                    axi_bvalid <= 1'b1;
                end else if (write_address == OSD_ADDRESS) begin
                    osd_write_address <= write_data[10:0];
                    axi_bvalid <= 1'b1;
                end else if (write_address == OSD_DATA) begin
                    osd_chars[osd_write_address] <= write_data[7:0];
                    osd_write_address <= osd_write_address + 1'b1;
                    axi_bvalid <= 1'b1;
                end else if (write_address == OSD_CONTROL) begin
                    osd_active <= write_data[0];
                    osd_narrow_selection <= write_data[1];
                    osd_option_selection <= write_data[2];
                    osd_selected_row <= write_data[12:8];
                    axi_bvalid <= 1'b1;
                end else if (write_address == OSD_FONT_STYLE) begin
                    osd_font_style <= write_data[1:0];
                    axi_bvalid <= 1'b1;
                end else if (write_address == VIDEO_SETTINGS) begin
                    // Bits 1:0 and 7 select Off/Thin/Classic/MAME/XRoar.
                    // Bits 3:2 independently select the artifact color pair.
                    artifact_mode <= {write_data[7], write_data[1:0]};
                    artifact_palette <= write_data[3:2];
                    coco2_palette <= {write_data[8], write_data[6:4]};
                    axi_bvalid <= 1'b1;
                end else if (write_address == TEXT_SETTINGS) begin
                    text_color_theme <= write_data[3:0];
                    axi_bvalid <= 1'b1;
                end else if (write_address == OSD_PREVIEW_ADDRESS) begin
                    osd_preview_write_address <= write_data[11:0];
                    axi_bvalid <= 1'b1;
                end else if (write_address == OSD_PREVIEW_DATA) begin
                    if (osd_preview_write_address < 12'd3174) begin
                        osd_preview_words[osd_preview_write_address] <= write_data;
                        osd_preview_write_address <= osd_preview_write_address + 1'b1;
                    end
                    axi_bvalid <= 1'b1;
                end else if (write_address == OSD_PREVIEW_PALETTE) begin
                    osd_preview_palette[write_data[11:8]*8 +: 8] <= write_data[7:0];
                    axi_bvalid <= 1'b1;
                end else if (write_address == OSD_PREVIEW_CONTROL) begin
                    osd_preview_active <= write_data[0];
                    axi_bvalid <= 1'b1;
                end else if (write_address == SERIAL_KEY_LO) begin
                    serial_keyboard_keys[31:0] <= write_data;
                    axi_bvalid <= 1'b1;
                end else if (write_address == SERIAL_KEY_HI) begin
                    serial_keyboard_keys[55:32] <= write_data[23:0];
                    axi_bvalid <= 1'b1;
                end else if (write_address == SERIAL_KEY_CONTROL) begin
                    serial_keyboard_shift <= write_data[0];
                    serial_keyboard_shift_override <= write_data[1];
                    if (write_data[8]) begin
                        serial_keyboard_keys <= 56'b0;
                        serial_keyboard_shift <= 1'b0;
                        serial_keyboard_shift_override <= 1'b0;
                    end
                    axi_bvalid <= 1'b1;
                end else if (write_address == SERIAL_FUNCTION_KEYS) begin
                    serial_function_keys <= write_data[7:0];
                    axi_bvalid <= 1'b1;
                end else if (write_address == SERIAL_MACHINE_CONTROL) begin
                    serial_cold_reset <= write_data[0];
                    serial_trace_enable <= write_data[2];
                    if (write_data[3])
                        serial_trace_snapshot_toggle <=
                            ~serial_trace_snapshot_toggle;
                    if (write_data[1]) begin
                        serial_keyboard_keys <= 56'b0;
                        serial_keyboard_shift <= 1'b0;
                        serial_keyboard_shift_override <= 1'b0;
                        serial_function_keys <= 8'b0;
                    end
                    axi_bvalid <= 1'b1;
                end else if (write_address == UART_CONTROL) begin
                    // Hold the shared TX pin on the manager UART throughout
                    // binary frame transfers, including inter-byte idle gaps.
                    uart_claim <= write_data[0];
                    axi_bvalid <= 1'b1;
                end else if (write_address == VIDEO_CAPTURE_CONTROL) begin
                    video_capture_stripe <= write_data[10:8];
                    if (write_data[0])
                        video_capture_request_toggle <=
                            ~video_capture_request_toggle;
                    axi_bvalid <= 1'b1;
                end else if (write_address == VIDEO_CAPTURE_ADDRESS) begin
                    video_capture_read_address <= write_data[15:0];
                    axi_bvalid <= 1'b1;
                end else if (write_address == PHYSICAL_FLOPPY_CONTROL) begin
                    physical_floppy_motor_request <= write_data[0];
                    physical_floppy_direction_request <= write_data[3];
                    physical_floppy_side_select_request <= write_data[4];
                    if (write_data[1])
                        physical_floppy_home_request_toggle <=
                            ~physical_floppy_home_request_toggle;
                    if (write_data[2])
                        physical_floppy_abort_request_toggle <=
                            ~physical_floppy_abort_request_toggle;
                    if (write_data[5])
                        physical_floppy_step_request_toggle <=
                            ~physical_floppy_step_request_toggle;
                    axi_bvalid <= 1'b1;
                end else if (write_address == CARTRIDGE_ADDRESS) begin
                    cartridge_address <= write_data[14:0];
                    axi_bvalid <= 1'b1;
                end else if (write_address == CARTRIDGE_DATA) begin
                    cartridge_data <= write_data[7:0];
                    cartridge_write <= 1'b1;
                    cartridge_signature <= {cartridge_signature[30:0],
                                            cartridge_signature[31]} ^
                                           {11'b0, cartridge_address,
                                            write_data[7:0]};
                    // Hold the selected address through the following clock.
                    // cartridge_write and cartridge_data are registered, so
                    // the dual-port ROM-Pak RAM consumes them one clock after
                    // this AXI transaction. Advancing the address here shifts
                    // every downloaded byte by one while the stream checksum
                    // still appears correct. Firmware explicitly writes the
                    // address for every mirrored cartridge byte.
                    axi_bvalid <= 1'b1;
                end else if (write_address == CARTRIDGE_CONTROL) begin
                    cartridge_enabled <= write_data[0];
                    cartridge_launch <= write_data[1];
                    if (!write_data[0])
                        cartridge_signature <= 32'b0;
                    axi_bvalid <= 1'b1;
                end else if (write_address == BIN_FIFO_DATA) begin
                    // A simultaneous CoCo pop creates room even when the FIFO
                    // began this clock full.  In that case occupancy is stable.
                    if (bin_fifo_count != 5'd16 || bin_fifo_pop_now) begin
                        bin_fifo[bin_fifo_write_pointer] <= write_data[7:0];
                        bin_fifo_write_pointer <= bin_fifo_write_pointer + 1'b1;
                        if (!bin_fifo_pop_now)
                            bin_fifo_count <= bin_fifo_count + 1'b1;
                        else
                            bin_fifo_count <= bin_fifo_count;
                    end
                    axi_bvalid <= 1'b1;
                end else if (write_address == BIN_FIFO_CONTROL) begin
                    if (write_data[0]) begin
                        bin_fifo_write_pointer <= 0;
                        bin_fifo_read_pointer <= 0;
                        bin_fifo_count <= 0;
                        bin_loader_done_seen <= 1'b0;
                        bin_cancelled <= 1'b0;
                    end
                    bin_transfer_active <= write_data[1];
                    bin_transfer_complete <= write_data[2];
                    bin_transfer_error <= write_data[3];
                    axi_bvalid <= 1'b1;
                end else if (write_address == FDC_ACK) begin
                    // Require a complete sector and delay publication.  The
                    // request toggle is captured here so a later request can
                    // never be acknowledged by this sector generation.
                    // A demand-paged drive must publish a complete 256-byte
                    // sector bank before acknowledging.  Drive 0 instead
                    // reads directly from the committed full-disk cache and
                    // must not depend on the unrelated sector-bank count.
                    fdc_ack_toggle_pending <= fdc_request_toggle;
`ifdef WUKONG_DISK_PREFETCH
                    if (write_data[0] && disk_cache_fdc_valid) begin
                        disk_sector_base_address <=
                            {disk_cache_fdc_address[19:8], 8'b0};
                        disk_sector_request_toggle <=
                            ~disk_sector_request_toggle;
                        disk_sector_ack_wait <= 1'b1;
                        fdc_ack_success_pending <= 1'b1;
                    end else begin
                        fdc_ack_success_pending <= write_data[0] &&
                                                   fdc_buffer_fill_count == 9'd256;
                        fdc_ack_delay <= 2'd2;
                        fdc_ack_pending <= 1'b1;
                    end
`else
                    fdc_ack_success_pending <= write_data[0] &&
                                               (disk_cache_fdc_valid ||
                                                fdc_buffer_fill_count == 9'd256);
                    fdc_ack_delay <= 2'd2;
                    fdc_ack_pending <= 1'b1;
`endif
                    axi_bvalid <= 1'b1;
                end else if (write_address == FDC_WRITE_ACK) begin
                    fdc_write_success <= write_data[0];
                    fdc_write_done_toggle <= fdc_write_complete_toggle;
                    axi_bvalid <= 1'b1;
                end else if (write_address == MOUNT_STATUS) begin
                    fdc_present <= write_data[2:0];
                    manager_ready <= write_data[8];
                    axi_bvalid <= 1'b1;
                end else begin
                    axi_bvalid <= 1'b1;
                end
            end
            if (await_spi) begin
                if (spi_busy) spi_seen_busy <= 1'b1;
                else if (spi_seen_busy) begin
                    await_spi <= 1'b0;
                    axi_bvalid <= 1'b1;
                end
            end
            if (axi_bvalid && axi_bready) begin
                axi_bvalid <= 1'b0;
                transaction_active <= 1'b0;
                have_address <= 1'b0;
                have_data <= 1'b0;
            end
            if (axi_arvalid && axi_arready) begin
                axi_rvalid <= 1'b1;
                case (axi_araddr)
                    UART_STATUS: axi_rdata <= {31'b0, uart_busy};
                    UART_RX_DATA: axi_rdata <= uart_rx_count != 0
                        ? {24'b0, uart_rx_fifo[uart_rx_read_pointer]} : 32'b0;
                    UART_RX_STATUS: axi_rdata <= {8'b0, uart_rx_frame_seen,
                        uart_rx_overflow, uart_rx_count, 15'b0,
                        uart_rx_count == 5'd16, uart_rx_count != 0};
                    SPI_CTRL: axi_rdata <= {16'b0, spi_divider, 7'b0, sd_cs_n};
                    SPI_XFER: axi_rdata <= {31'b0, spi_busy};
                    SPI_DATA: axi_rdata <= {24'b0, spi_rx};
                    FDC_STATE: axi_rdata <= {19'b0, fdc_write_complete_toggle, fdc_read_complete_toggle, fdc_present, 6'b0,
                                               fdc_done_toggle, fdc_request_toggle};
                    FDC_INFO: axi_rdata <= {fdc_last_type1, fdc_track,
                                              fdc_sector, 5'b0, fdc_side,
                                              fdc_drive};
                    MOUNT_STATUS: axi_rdata <= {23'b0, manager_ready, 5'b0, fdc_present};
                    FDC_BUFFER_PEEK: axi_rdata <= {24'b0, fdc_buffer_data};
                    FDC_DEBUG_WORD: axi_rdata <= fdc_debug_word;
                    FDC_COMPLETED_DEBUG_WORD: axi_rdata <= fdc_completed_debug_word;
                    FDC_BUFFER_DEBUG_DATA: axi_rdata <= {24'b0,
                        fdc_buffer_write_bank
                        ? fdc_buffer1[fdc_buffer_debug_address]
                        : fdc_buffer0[fdc_buffer_debug_address]};
                    FDC_WRITE_BUFFER_DEBUG_DATA: axi_rdata <= {24'b0, fdc_write_buffer[fdc_buffer_debug_address]};
                    DISK_CACHE_STATUS: axi_rdata <= {11'b0,
                        disk_cache_write_address, disk_cache_ready};
                    DISK_CACHE_DEBUG_DATA: axi_rdata <= {24'b0, disk_cache_fdc_data};
                    OSD_CONTROL: axi_rdata <= {19'b0, osd_selected_row, 5'b0,
                                               osd_option_selection,
                                               osd_narrow_selection, osd_active};
                    OSD_PREVIEW_CONTROL: axi_rdata <= {31'b0, osd_preview_active};
                    PHYSICAL_FLOPPY_STATUS: axi_rdata <= {
                        16'b0, physical_floppy_home_step_count,
                        physical_floppy_home_success,
                        physical_floppy_home_done_toggle,
                        physical_floppy_home_active,
                        physical_floppy_motor_active,
                        physical_floppy_present,
                        physical_floppy_status};
                    PHYSICAL_FLOPPY_INDEX_COUNT:
                        axi_rdata <= physical_floppy_index_count;
                    PHYSICAL_FLOPPY_READ_COUNT:
                        axi_rdata <= physical_floppy_read_transition_count;
                    PHYSICAL_FLOPPY_CONTROL:
                        axi_rdata <= {26'b0,
                                      physical_floppy_step_request_toggle,
                                      physical_floppy_side_select_request,
                                      physical_floppy_direction_request,
                                      physical_floppy_abort_request_toggle,
                                      physical_floppy_home_request_toggle,
                                      physical_floppy_motor_request};
                    MENU_KEY_STATE: axi_rdata <= {22'b0, menu_key_state};
                    OSD_FONT_STYLE: axi_rdata <= {30'b0, osd_font_style};
                    VIDEO_SETTINGS: axi_rdata <= {23'b0, coco2_palette[3],
                        artifact_mode[2], coco2_palette[2:0],
                        artifact_palette, artifact_mode[1:0]};
                    TEXT_SETTINGS: axi_rdata <= {28'b0, text_color_theme};
                    SERIAL_KEY_LO: axi_rdata <= serial_keyboard_keys[31:0];
                    SERIAL_KEY_HI: axi_rdata <= {8'b0, serial_keyboard_keys[55:32]};
                    SERIAL_KEY_CONTROL: axi_rdata <= {30'b0,
                        serial_keyboard_shift_override, serial_keyboard_shift};
                    SERIAL_FUNCTION_KEYS: axi_rdata <= {24'b0, serial_function_keys};
                    DEBUG_CPU_STATUS: axi_rdata <= {16'b0, debug_cpu_pc};
                    DEBUG_VIDEO_STATUS: axi_rdata <= {debug_gime_init0,
                        debug_gime_init1, debug_video_mode, debug_video_resolution};
                    UART_CONTROL: axi_rdata <= {31'b0, uart_claim};
                    VIDEO_CAPTURE_STATUS: axi_rdata <= {30'b0,
                        video_capture_busy, video_capture_done_toggle};
                    VIDEO_CAPTURE_ADDRESS: axi_rdata <= {16'b0,
                        video_capture_read_address};
                    VIDEO_CAPTURE_DATA: begin
                        axi_rdata <= {24'b0, video_capture_read_data};
                        if (video_capture_read_address != 16'hffff)
                            video_capture_read_address <=
                                video_capture_read_address + 1'b1;
                    end
                    CARTRIDGE_SIGNATURE: axi_rdata <= cartridge_signature;
                    BIN_FIFO_STATUS: axi_rdata <= {
                        11'b0, bin_cancelled, bin_transfer_error,
                        bin_transfer_complete, bin_transfer_active,
                        bin_loader_done_seen, 6'b0,
                        bin_fifo_count == 0, bin_fifo_count == 5'd16,
                        3'b0, bin_fifo_count};
                    default: axi_rdata <= 0;
                endcase
            end else if (axi_rvalid && axi_rready) axi_rvalid <= 1'b0;
            // CoCo reset/cancel and loader completion take precedence over an
            // in-flight producer operation and also remove the temporary cart.
            if (bin_cancel) begin
                bin_fifo_write_pointer <= 0;
                bin_fifo_read_pointer <= 0;
                bin_fifo_count <= 0;
                bin_transfer_active <= 1'b0;
                bin_transfer_complete <= 1'b0;
                bin_transfer_error <= 1'b0;
                bin_loader_done_seen <= 1'b0;
                bin_cancelled <= 1'b1;
                cartridge_enabled <= 1'b0;
            end else if (bin_loader_done) begin
                bin_transfer_active <= 1'b0;
                bin_loader_done_seen <= 1'b1;
                cartridge_enabled <= 1'b0;
            end
        end
    end
    wire _unused = &{axi_wstrb};
endmodule

`ifdef WUKONG_DISK_PREFETCH
`undef WUKONG_DISK_PREFETCH
`endif
`ifdef WUKONG_SHARED_DISK_CACHE
`undef WUKONG_SHARED_DISK_CACHE
`endif
`default_nettype wire
