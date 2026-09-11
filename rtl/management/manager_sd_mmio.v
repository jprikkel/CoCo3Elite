`timescale 1ns/1ps
`default_nettype none

// Project-owned AXI-Lite peripheral for the manager firmware smoke test.
// 0x80000000 UART byte write; 0x80000004 UART busy (bit 0).
// 0x80000100 SPI control: bit 0 CS_n, bits 15:8 half-period divider.
// 0x80000104 SPI transfer byte write (response is delayed until byte complete).
// 0x80000108 SPI received byte read.  0x80000200..214 are the FDC mailbox and
// its 256-byte shared read buffer.  The delayed write response is intentional:
// it makes one MMIO store exactly one synchronous SPI byte transaction.
module manager_sd_mmio #(
    parameter integer UART_CLKS_PER_BIT = 434,
    parameter integer DISK_CACHE_BYTES = 161280
) (
    input wire clock, input wire reset,
    input wire axi_awvalid, output wire axi_awready, input wire [31:0] axi_awaddr,
    input wire axi_wvalid, output wire axi_wready, input wire [31:0] axi_wdata,
    input wire [3:0] axi_wstrb, output reg axi_bvalid, input wire axi_bready,
    output wire [1:0] axi_bresp,
    input wire axi_arvalid, output wire axi_arready, input wire [31:0] axi_araddr,
    output reg axi_rvalid, input wire axi_rready, output reg [31:0] axi_rdata,
    output wire [1:0] axi_rresp,
    output wire uart_tx, output reg sd_cs_n, output reg sd_sck, output reg sd_mosi,
    input wire sd_miso,
    input wire [1:0] fdc_drive, input wire [7:0] fdc_track,
    input wire [7:0] fdc_sector, input wire [7:0] fdc_last_type1, input wire [31:0] fdc_debug_word, input wire [31:0] fdc_completed_debug_word, input wire fdc_read_complete_toggle, input wire fdc_write_complete_toggle, input wire fdc_request_toggle,
    input wire [7:0] fdc_buffer_address, output wire [7:0] fdc_buffer_data,
    input wire fdc_write_strobe, input wire [7:0] fdc_write_data,
    input wire [4:0] menu_key_state,
    input wire [9:0] osd_char_address,
    output wire [7:0] osd_char_data,
    output reg osd_active,
    output reg [4:0] osd_selected_row,
    output reg fdc_done_toggle, output reg fdc_success,
    output reg fdc_write_done_toggle, output reg fdc_write_success,
    output reg [2:0] fdc_present, output reg manager_ready
);
    localparam UART_DATA = 32'h80000000, UART_STATUS = 32'h80000004,
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
               MENU_KEY_STATE = 32'h80000258;
    reg have_address, have_data, transaction_active, await_spi, spi_seen_busy;
    reg [31:0] write_address, write_data;
    reg [7:0] spi_tx, spi_rx, spi_tx_shift, spi_rx_shift;
    reg [7:0] spi_divider, spi_divider_count;
    reg [3:0] spi_bit_count;
    reg spi_busy, spi_start;
    reg [7:0] uart_data;
    reg uart_start;
    (* ram_style = "distributed" *) reg [7:0] osd_chars [0:1023];
    reg [9:0] osd_write_address;
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
    // Drive 0 is the known-good reference path: firmware loads the complete
    // 35-track image once, then the FDC reads it directly from block RAM.
    // The two small sector banks above are reserved for later drive 1/2
    // demand paging and are never selected for a mounted drive 0.
    reg [17:0] disk_cache_write_address;
    reg [17:0] disk_cache_debug_address;
    reg disk_cache_ready;
    wire [7:0] disk_cache_fdc_data;
    wire [10:0] disk_cache_linear_sector = ({3'b000, fdc_track} << 4) +
                                            ({3'b000, fdc_track} << 1) +
                                            {3'b000, fdc_sector} - 11'd1;
    wire [18:0] disk_cache_fdc_address = {disk_cache_linear_sector, fdc_buffer_address};
    wire disk_cache_fdc_valid = disk_cache_ready && fdc_drive == 2'd0 &&
                                fdc_track < 8'd35 && fdc_sector >= 8'd1 && fdc_sector <= 8'd18;
    wire uart_busy;
    // The firmware owns FAT32 and fills this sector buffer completely before
    // acknowledging an FDC read.  The FDC then consumes a stable, asynchronous
    // 256-byte buffer, preserving normal CoCo Disk BASIC timing.
    wire [7:0] sector_cache_data = fdc_buffer_read_bank
                                 ? fdc_buffer1[fdc_buffer_address]
                                 : fdc_buffer0[fdc_buffer_address];
    assign fdc_buffer_data = disk_cache_fdc_valid ? disk_cache_fdc_data
                                                  : sector_cache_data;
    assign osd_char_data = osd_chars[osd_char_address];

    assign axi_awready = !have_address && !transaction_active;
    assign axi_wready = !have_data && !transaction_active;
    assign axi_bresp = 2'b00;
    assign axi_arready = !axi_rvalid;
    assign axi_rresp = 2'b00;

    wire disk_cache_load_write = !reset && !transaction_active &&
                                 have_address && have_data &&
                                 write_address == DISK_CACHE_DATA &&
                                 disk_cache_write_address < DISK_CACHE_BYTES;
    wire disk_cache_fdc_write = fdc_write_strobe && disk_cache_fdc_valid;
    wire disk_cache_port_write = disk_cache_fdc_write || disk_cache_load_write;
    wire [17:0] disk_cache_port_write_address = disk_cache_fdc_write
                                                ? disk_cache_fdc_address[17:0]
                                                : disk_cache_write_address;
    wire [7:0] disk_cache_port_write_data = disk_cache_fdc_write
                                           ? fdc_write_data : write_data[7:0];
    // Firmware may inspect the cache only before it marks the manager ready;
    // afterward port B belongs exclusively to the live FDC.
    wire [17:0] disk_cache_read_address = manager_ready
                                          ? disk_cache_fdc_address[17:0]
                                          : disk_cache_debug_address;

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
        .addra(disk_cache_port_write_address), .dina(disk_cache_port_write_data),
        .enb(1'b1), .addrb(disk_cache_read_address),
        .doutb(disk_cache_fdc_data), .regceb(1'b1), .rstb(reset),
        .sleep(1'b0), .injectdbiterra(1'b0), .injectsbiterra(1'b0),
        .dbiterrb(), .sbiterrb()
    );

    uart_tx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) uart_i (
        .clock(clock), .reset(reset), .data(uart_data), .start(uart_start),
        .tx(uart_tx), .busy(uart_busy)
    );

    // The FDC owns the write staging buffer.  Firmware reads it after the
    // complete 256-byte sector transfer and merges it into the FAT32 block.
    always @(posedge clock) begin
        if (fdc_write_strobe && fdc_present[0] && fdc_drive == 2'd0 &&
            fdc_track < 8'd35 && fdc_sector >= 8'd1 && fdc_sector <= 8'd18) begin
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
            disk_cache_ready <= 1'b0;
            osd_write_address <= 0;
            osd_active <= 1'b0;
            osd_selected_row <= 0;
            fdc_done_toggle <= 0; fdc_success <= 0;
            fdc_write_done_toggle <= 0; fdc_write_success <= 0;
            fdc_present <= 0; manager_ready <= 0;
        end else begin
            // Registered block-RAM read matches the proven embedded/full-disk
            // timing. During a CoCo write, update the cached byte immediately;
            // firmware separately persists the staged sector to FAT32.
            spi_start <= 0;
            uart_start <= 0;
            // Publish a filled sector only after the complete 256-byte MMIO
            // write stream has retired and the buffer has remained stable for
            // additional clocks.  This prevents the FDC from observing the
            // previous sector when firmware immediately follows the final
            // data store with FDC_ACK.
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
            if (!transaction_active && have_address && have_data) begin
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
                    axi_bvalid <= 1'b1;
                end else if (write_address == DISK_CACHE_DATA) begin
                    if (disk_cache_write_address < DISK_CACHE_BYTES) begin
                        disk_cache_write_address <= disk_cache_write_address + 1'b1;
                    end
                    axi_bvalid <= 1'b1;
                end else if (write_address == DISK_CACHE_COMMIT) begin
                    disk_cache_ready <= write_data[0] &&
                                        disk_cache_write_address == DISK_CACHE_BYTES;
                    axi_bvalid <= 1'b1;
                end else if (write_address == DISK_CACHE_DEBUG_ADDRESS) begin
                    disk_cache_debug_address <= write_data[17:0];
                    axi_bvalid <= 1'b1;
                end else if (write_address == OSD_ADDRESS) begin
                    osd_write_address <= write_data[9:0];
                    axi_bvalid <= 1'b1;
                end else if (write_address == OSD_DATA) begin
                    osd_chars[osd_write_address] <= write_data[7:0];
                    osd_write_address <= osd_write_address + 1'b1;
                    axi_bvalid <= 1'b1;
                end else if (write_address == OSD_CONTROL) begin
                    osd_active <= write_data[0];
                    osd_selected_row <= write_data[12:8];
                    axi_bvalid <= 1'b1;
                end else if (write_address == FDC_ACK) begin
                    // Require a complete sector and delay publication.  The
                    // request toggle is captured here so a later request can
                    // never be acknowledged by this sector generation.
                    fdc_ack_success_pending <= write_data[0] &&
                                               fdc_buffer_fill_count == 9'd256;
                    fdc_ack_toggle_pending <= fdc_request_toggle;
                    fdc_ack_delay <= 2'd2;
                    fdc_ack_pending <= 1'b1;
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
                    SPI_CTRL: axi_rdata <= {16'b0, spi_divider, 7'b0, sd_cs_n};
                    SPI_XFER: axi_rdata <= {31'b0, spi_busy};
                    SPI_DATA: axi_rdata <= {24'b0, spi_rx};
                    FDC_STATE: axi_rdata <= {19'b0, fdc_write_complete_toggle, fdc_read_complete_toggle, fdc_present, 6'b0,
                                               fdc_done_toggle, fdc_request_toggle};
                    FDC_INFO: axi_rdata <= {fdc_last_type1, fdc_track, fdc_sector, 6'b0, fdc_drive};
                    MOUNT_STATUS: axi_rdata <= {23'b0, manager_ready, 5'b0, fdc_present};
                    FDC_BUFFER_PEEK: axi_rdata <= {24'b0, fdc_buffer_data};
                    FDC_DEBUG_WORD: axi_rdata <= fdc_debug_word;
                    FDC_COMPLETED_DEBUG_WORD: axi_rdata <= fdc_completed_debug_word;
                    FDC_BUFFER_DEBUG_DATA: axi_rdata <= {24'b0,
                        fdc_buffer_write_bank
                        ? fdc_buffer1[fdc_buffer_debug_address]
                        : fdc_buffer0[fdc_buffer_debug_address]};
                    FDC_WRITE_BUFFER_DEBUG_DATA: axi_rdata <= {24'b0, fdc_write_buffer[fdc_buffer_debug_address]};
                    DISK_CACHE_STATUS: axi_rdata <= {13'b0,
                        disk_cache_write_address, disk_cache_ready};
                    DISK_CACHE_DEBUG_DATA: axi_rdata <= {24'b0, disk_cache_fdc_data};
                    OSD_CONTROL: axi_rdata <= {19'b0, osd_selected_row, 7'b0, osd_active};
                    MENU_KEY_STATE: axi_rdata <= {27'b0, menu_key_state};
                    default: axi_rdata <= 0;
                endcase
            end else if (axi_rvalid && axi_rready) axi_rvalid <= 1'b0;
        end
    end
    wire _unused = &{axi_wstrb};
endmodule

`default_nettype wire
