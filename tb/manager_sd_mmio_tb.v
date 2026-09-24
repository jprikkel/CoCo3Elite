`timescale 1ns/1ps
`default_nettype none
module manager_sd_mmio_tb;
    reg clock = 0, reset = 1;
    always #5 clock = ~clock;
    reg awvalid = 0, wvalid = 0, bready = 1, arvalid = 0, rready = 1;
    reg [31:0] awaddr = 0, wdata = 0, araddr = 0;
    reg [3:0] wstrb = 4'hf;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    wire uart_tx, uart_claim, sd_cs_n, sd_sck, sd_mosi;
    wire video_capture_request_toggle;
    wire [2:0] video_capture_stripe;
    wire [15:0] video_capture_read_address;
    reg [7:0] video_capture_read_data = 8'ha5;
    reg video_capture_done_toggle = 0, video_capture_busy = 0;
    reg physical_floppy_present = 1;
    reg [2:0] physical_floppy_status = 3'b110;
    reg [31:0] physical_floppy_index_count = 32'h12345678;
    reg [31:0] physical_floppy_read_transition_count = 32'h9abcdef0;
    reg physical_floppy_motor_active = 1'b1;
    reg physical_floppy_home_active = 1'b0;
    reg physical_floppy_home_done_toggle = 1'b1;
    reg physical_floppy_home_success = 1'b1;
    reg [7:0] physical_floppy_home_step_count = 8'h2a;
    wire physical_floppy_motor_request;
    wire physical_floppy_direction_request;
    wire physical_floppy_side_select_request;
    wire physical_floppy_step_request_toggle;
    wire physical_floppy_home_request_toggle;
    wire physical_floppy_abort_request_toggle;
    wire physical_floppy_decode_request_toggle;
    wire [12:0] physical_floppy_decode_cache_address;
    reg physical_floppy_decode_busy = 1'b0;
    reg physical_floppy_decode_done_toggle = 1'b1;
    reg physical_floppy_decode_success = 1'b1;
    reg [7:0] physical_floppy_decode_track = 8'h11;
    reg physical_floppy_decode_side = 1'b1;
    reg [17:0] physical_floppy_decode_sector_valid = 18'h3ffff;
    reg [7:0] physical_floppy_decode_id_crc_errors = 8'h02;
    reg [7:0] physical_floppy_decode_data_crc_errors = 8'h03;
    reg [7:0] physical_floppy_decode_cache_data = 8'ha6;
    wire [14:0] cartridge_address;
    wire [7:0] cartridge_data;
    wire cartridge_write, cartridge_enabled, cartridge_launch;
    reg bin_fifo_pop = 0, bin_loader_done = 0, bin_cancel = 0;
    wire [7:0] bin_fifo_data;
    wire bin_fifo_available, bin_transfer_active;
    wire bin_transfer_complete, bin_transfer_error;
    wire [7:0] cartridge_cpu_data;
    reg fdc_request_toggle = 0;
    reg [7:0] fdc_buffer_address = 0;
    reg fdc_write_strobe = 0;
    reg [7:0] fdc_write_data = 0;
    reg [9:0] menu_key_state = 0;
    reg [10:0] osd_char_address = 0;
    wire [7:0] osd_char_data;
    reg [11:0] osd_preview_read_address = 0;
    wire [31:0] osd_preview_read_data;
    wire osd_preview_active;
    wire [127:0] osd_preview_palette;
    wire osd_active;
    wire [4:0] osd_selected_row;
    wire osd_narrow_selection;
    wire osd_option_selection;
    wire [1:0] osd_font_style;
    wire [2:0] artifact_mode;
    wire [1:0] artifact_palette;
    wire [3:0] coco2_palette;
    wire [3:0] text_color_theme;
    wire [55:0] serial_keyboard_keys;
    wire serial_keyboard_shift, serial_keyboard_shift_override;
    wire [7:0] serial_function_keys;
    wire serial_cold_reset;
    wire fdc_done_toggle, fdc_success;
    wire [7:0] fdc_buffer_data;
    integer rising_edges = 0;
    always @(posedge sd_sck) rising_edges = rising_edges + 1;
    reg saw_cartridge_write = 0, saw_cartridge_launch = 0;
    reg [14:0] captured_cartridge_address = 0;
    reg [7:0] captured_cartridge_data = 0;
    always @(posedge clock) begin
        if (reset) begin
            saw_cartridge_write <= 0;
            saw_cartridge_launch <= 0;
        end else begin
            if (cartridge_write) begin
                saw_cartridge_write <= 1;
                captured_cartridge_address <= cartridge_address;
                captured_cartridge_data <= cartridge_data;
            end
            if (cartridge_launch) saw_cartridge_launch <= 1;
        end
    end

    manager_sd_mmio #(.UART_CLKS_PER_BIT(2), .DISK_CACHE_BYTES(512)) dut (
        .clock(clock), .reset(reset), .axi_awvalid(awvalid), .axi_awready(awready),
        .axi_awaddr(awaddr), .axi_wvalid(wvalid), .axi_wready(wready), .axi_wdata(wdata),
        .axi_wstrb(wstrb), .axi_bvalid(bvalid), .axi_bready(bready), .axi_bresp(bresp),
        .axi_arvalid(arvalid), .axi_arready(arready), .axi_araddr(araddr), .axi_rvalid(rvalid),
        .axi_rready(rready), .axi_rdata(rdata), .axi_rresp(rresp), .uart_tx(uart_tx),
        .uart_rx(1'b1), .uart_claim(uart_claim),
        .sd_cs_n(sd_cs_n), .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(1'b1),
        .fdc_drive(2'd0), .fdc_side(1'b0),
        .fdc_track(8'd0), .fdc_sector(8'd1),
        .fdc_last_type1(8'h17), .fdc_debug_word(32'd0),
        .fdc_completed_debug_word(32'd0), .fdc_read_complete_toggle(1'b0),
        .fdc_write_complete_toggle(1'b0),
        .fdc_request_toggle(fdc_request_toggle), .fdc_buffer_address(fdc_buffer_address),
        .fdc_buffer_data(fdc_buffer_data), .fdc_write_strobe(fdc_write_strobe),
        .fdc_write_data(fdc_write_data),
        .menu_key_state(menu_key_state), .osd_char_address(osd_char_address),
        .osd_char_data(osd_char_data), .osd_active(osd_active),
        .osd_preview_read_address(osd_preview_read_address),
        .osd_preview_read_data(osd_preview_read_data),
        .osd_preview_active(osd_preview_active),
        .osd_preview_palette(osd_preview_palette),
        .osd_selected_row(osd_selected_row),
        .osd_narrow_selection(osd_narrow_selection),
        .osd_option_selection(osd_option_selection),
        .osd_font_style(osd_font_style),
        .artifact_mode(artifact_mode),.artifact_palette(artifact_palette),
        .coco2_palette(coco2_palette),
        .text_color_theme(text_color_theme),
        .serial_keyboard_keys(serial_keyboard_keys),
        .serial_keyboard_shift(serial_keyboard_shift),
        .serial_keyboard_shift_override(serial_keyboard_shift_override),
        .serial_function_keys(serial_function_keys),
        .serial_cold_reset(serial_cold_reset),
        .debug_cpu_pc(16'ha7d5), .debug_gime_init0(8'h40),
        .debug_gime_init1(8'h00), .debug_video_mode(8'h80),
        .debug_video_resolution(8'h12),
        .physical_floppy_present(physical_floppy_present),
        .physical_floppy_status(physical_floppy_status),
        .physical_floppy_index_count(physical_floppy_index_count),
        .physical_floppy_read_transition_count(
            physical_floppy_read_transition_count),
        .physical_floppy_motor_request(physical_floppy_motor_request),
        .physical_floppy_direction_request(
            physical_floppy_direction_request),
        .physical_floppy_side_select_request(
            physical_floppy_side_select_request),
        .physical_floppy_step_request_toggle(
            physical_floppy_step_request_toggle),
        .physical_floppy_home_request_toggle(
            physical_floppy_home_request_toggle),
        .physical_floppy_abort_request_toggle(
            physical_floppy_abort_request_toggle),
        .physical_floppy_motor_active(physical_floppy_motor_active),
        .physical_floppy_home_active(physical_floppy_home_active),
        .physical_floppy_home_done_toggle(physical_floppy_home_done_toggle),
        .physical_floppy_home_success(physical_floppy_home_success),
        .physical_floppy_home_step_count(physical_floppy_home_step_count),
        .physical_floppy_decode_request_toggle(
            physical_floppy_decode_request_toggle),
        .physical_floppy_decode_cache_address(
            physical_floppy_decode_cache_address),
        .physical_floppy_decode_busy(physical_floppy_decode_busy),
        .physical_floppy_decode_done_toggle(
            physical_floppy_decode_done_toggle),
        .physical_floppy_decode_success(physical_floppy_decode_success),
        .physical_floppy_decode_track(physical_floppy_decode_track),
        .physical_floppy_decode_side(physical_floppy_decode_side),
        .physical_floppy_decode_sector_valid(
            physical_floppy_decode_sector_valid),
        .physical_floppy_decode_id_crc_errors(
            physical_floppy_decode_id_crc_errors),
        .physical_floppy_decode_data_crc_errors(
            physical_floppy_decode_data_crc_errors),
        .physical_floppy_decode_cache_data(
            physical_floppy_decode_cache_data),
        .video_capture_request_toggle(video_capture_request_toggle),
        .video_capture_stripe(video_capture_stripe),
        .video_capture_read_address(video_capture_read_address),
        .video_capture_read_data(video_capture_read_data),
        .video_capture_done_toggle(video_capture_done_toggle),
        .video_capture_busy(video_capture_busy),
        .fdc_done_toggle(fdc_done_toggle), .fdc_success(fdc_success),
        .fdc_write_done_toggle(), .fdc_write_success(), .fdc_present(),
        .manager_ready(), .cartridge_address(cartridge_address),
        .cartridge_data(cartridge_data), .cartridge_write(cartridge_write),
        .cartridge_enabled(cartridge_enabled), .cartridge_launch(cartridge_launch),
        .bin_fifo_pop(bin_fifo_pop), .bin_loader_done(bin_loader_done),
        .bin_cancel(bin_cancel), .bin_fifo_data(bin_fifo_data),
        .bin_fifo_available(bin_fifo_available),
        .bin_transfer_active(bin_transfer_active),
        .bin_transfer_complete(bin_transfer_complete),
        .bin_transfer_error(bin_transfer_error)
    );

    // Model the production consumer of the registered manager write port.
    // This catches address/data skew that a manager-only signal test misses.
    coco3_sd_cartridge cartridge_store (
        .clock(clock), .cpu_address(13'h1234),
        .cpu_data(cartridge_cpu_data),
        .manager_address(cartridge_address[12:0]),
        .manager_data(cartridge_data), .manager_write(cartridge_write)
    );

    task write32;
        input [31:0] address;
        input [31:0] value;
        begin
            // Drive on the falling edge so the DUT sees stable valid signals
            // at the next rising edge; this avoids a TB/DUT race.
            @(negedge clock);
            awaddr = address; wdata = value; awvalid = 1; wvalid = 1;
            @(posedge clock);
            #1 awvalid = 0; wvalid = 0;
            while (!bvalid) @(posedge clock);
            @(posedge clock);
        end
    endtask
    task read32;
        input [31:0] address;
        output [31:0] value;
        begin
            @(negedge clock);
            araddr = address; arvalid = 1;
            @(posedge clock); #1 arvalid = 0;
            while (!rvalid) @(posedge clock);
            value = rdata;
            @(posedge clock);
        end
    endtask
    reg [31:0] value;
    reg [31:0] expected_cartridge_signature;
    initial begin
        #200000;
        $fatal(1, "manager SD MMIO test timed out");
    end
    initial begin
        repeat (4) @(posedge clock);
        reset = 0;
        $display("checking serial keyboard and machine status MMIO");
        write32(32'h80000284, 32'h80000002);
        write32(32'h80000288, 32'h00800001);
        write32(32'h8000028c, 32'h00000003);
        write32(32'h80000290, 32'h00000082);
        if (serial_keyboard_keys !== 56'h80000180000002 ||
            !serial_keyboard_shift || !serial_keyboard_shift_override ||
            serial_function_keys !== 8'h82)
            $fatal(1, "serial keyboard state was not published");
        read32(32'h80000298, value);
        if (value[15:0] !== 16'ha7d5)
            $fatal(1, "CPU status readback mismatch");
        read32(32'h8000029c, value);
        if (value !== 32'h40008012)
            $fatal(1, "video status readback mismatch: %h", value);
        $display("checking physical floppy diagnostic MMIO");
        read32(32'h800002c4, value);
        if (value !== 32'h00002ade)
            $fatal(1, "physical floppy status mismatch: %h", value);
        read32(32'h800002c8, value);
        if (value !== 32'h12345678)
            $fatal(1, "physical floppy index count mismatch: %h", value);
        read32(32'h800002cc, value);
        if (value !== 32'h9abcdef0)
            $fatal(1, "physical floppy read count mismatch: %h", value);
        write32(32'h800002d0, 32'h00000019);
        if (!physical_floppy_motor_request ||
            !physical_floppy_direction_request ||
            !physical_floppy_side_select_request)
            $fatal(1, "physical floppy motor request was not published");
        read32(32'h800002d0, value);
        if (value !== 32'h00000019)
            $fatal(1, "physical floppy control readback mismatch: %h", value);
        write32(32'h800002d0, 32'h00000018);
        if (physical_floppy_motor_request)
            $fatal(1, "physical floppy motor request did not stop");
        write32(32'h800002d0, 32'h0000001a);
        if (!physical_floppy_home_request_toggle)
            $fatal(1, "physical floppy home event was not published");
        write32(32'h800002d0, 32'h0000001c);
        if (!physical_floppy_abort_request_toggle)
            $fatal(1, "physical floppy abort event was not published");
        write32(32'h800002d0, 32'h00000038);
        if (!physical_floppy_step_request_toggle)
            $fatal(1, "physical floppy step event was not published");
        read32(32'h800002d0, value);
        if (value[5:0] !== 6'b111110)
            $fatal(1, "physical floppy event readback mismatch: %h", value);
        write32(32'h800002fc, 32'h00000001);
        if (!physical_floppy_decode_request_toggle)
            $fatal(1, "physical floppy decode event was not published");
        write32(32'h80000308, 32'h00001123);
        if (physical_floppy_decode_cache_address !== 13'h1123)
            $fatal(1, "physical floppy decode address mismatch");
        read32(32'h80000300, value);
        if (value !== 32'h0203110d)
            $fatal(1, "physical floppy decode status mismatch: %h", value);
        read32(32'h80000304, value);
        if (value[17:0] !== 18'h3ffff)
            $fatal(1, "physical floppy sector bitmap mismatch: %h", value);
        read32(32'h8000030c, value);
        if (value[7:0] !== 8'ha6)
            $fatal(1, "physical floppy decode data mismatch: %h", value);
        $display("checking video capture and UART ownership MMIO");
        write32(32'h800002a0, 1);
        if (!uart_claim) $fatal(1, "manager UART claim was not retained");
        read32(32'h800002a0, value);
        if (value[0] !== 1'b1) $fatal(1, "manager UART claim readback failed");
        write32(32'h800002a4, 32'h00000501);
        if (video_capture_request_toggle !== 1'b1 ||
            video_capture_stripe !== 3'd5)
            $fatal(1, "video capture request/stripe mismatch");
        video_capture_done_toggle = 1;
        video_capture_busy = 1;
        read32(32'h800002a8, value);
        if (value[1:0] !== 2'b11)
            $fatal(1, "video capture status mismatch: %h", value[1:0]);
        write32(32'h800002ac, 16'd38399);
        read32(32'h800002b0, value);
        if (value[7:0] !== 8'ha5 || video_capture_read_address !== 16'd38400)
            $fatal(1, "video capture data/address mismatch: %h @ %0d",
                   value[7:0], video_capture_read_address);
        write32(32'h800002a0, 0);
        write32(32'h8000028c, 32'h00000100);
        write32(32'h80000290, 32'h00000000);
        if (serial_keyboard_keys !== 56'b0 || serial_keyboard_shift ||
            serial_keyboard_shift_override || serial_function_keys !== 0)
            $fatal(1, "serial keyboard release-all failed");
        $display("checking OSD character and input MMIO");
        if (osd_font_style != 2'd1)
            $fatal(1, "Tamzen is not the default management font");
        if (artifact_mode != 3'd5)
            $fatal(1, "Two pass is not the default artifact style");
        write32(32'h8000024c, 10'd12);
        write32(32'h80000250, 8'h41);
        osd_char_address = 10'd12; #1;
        if (osd_char_data !== 8'h41)
            $fatal(1, "OSD character RAM mismatch: %h", osd_char_data);
        write32(32'h8000024c, 11'd2015);
        write32(32'h80000250, 8'h90);
        osd_char_address = 11'd2015; #1;
        if (osd_char_data !== 8'h90)
            $fatal(1, "expanded OSD character RAM mismatch: %h", osd_char_data);
        write32(32'h800002b4, 12'd3172);
        write32(32'h800002b8, 32'hdeadbeef);
        write32(32'h800002b8, 32'h01234567);
        write32(32'h800002bc, 32'h00000ae3);
        write32(32'h800002c0, 1);
        write32(32'h80000254, (32'd7 << 8) | 7);
        osd_preview_read_address = 12'd3172;
        repeat (2) @(posedge clock); #1;
        if (osd_preview_read_data !== 32'hdeadbeef)
            $fatal(1, "preview RAM first word mismatch: %h", osd_preview_read_data);
        osd_preview_read_address = 12'd3173;
        repeat (2) @(posedge clock); #1;
        if (osd_preview_read_data !== 32'h01234567)
            $fatal(1, "preview RAM final word mismatch: %h", osd_preview_read_data);
        if (!osd_preview_active || osd_preview_palette[87:80] !== 8'he3)
            $fatal(1, "preview palette/control was not published");
        read32(32'h800002c0, value);
        if (!value[0]) $fatal(1, "preview control readback failed");
        if (!osd_active || !osd_narrow_selection || !osd_option_selection ||
            osd_selected_row != 5'd7)
            $fatal(1, "OSD control was not published");
        write32(32'h80000278, 32'd3);
        if (osd_font_style != 2'd3)
            $fatal(1, "OSD font style was not published");
        read32(32'h80000278, value);
        if (value[1:0] != 2'd3)
            $fatal(1, "OSD font style readback mismatch: %h", value[1:0]);
        // Bit 7 extends artifact style; bit 8 extends the CoCo palette.
        write32(32'h8000027c, 32'h000001f5);
        if(artifact_mode!=3'd5 || artifact_palette!=2'd1 || coco2_palette!=4'd15)
            $fatal(1,"video settings were not published");
        read32(32'h8000027c,value);
        if(value[8:0]!=9'h1f5)$fatal(1,"video settings readback mismatch: %h",value);
        write32(32'h80000280, 32'd9);
        if(text_color_theme!=4'd9)$fatal(1,"text theme was not published");
        read32(32'h80000280,value);
        if(value[3:0]!=4'd9)$fatal(1,"text theme readback mismatch: %h",value);
        menu_key_state = 10'b1110110101;
        read32(32'h80000258, value);
        if (value[9:0] !== 10'b1110110101)
            $fatal(1, "menu key state mismatch: %h", value[9:0]);
        $display("checking cartridge control ownership");
        write32(32'h80000264, 32'h0);
        write32(32'h8000025c, 15'h1234);
        write32(32'h80000260, 8'h5a);
        if (!saw_cartridge_write || cartridge_address != 15'h1234 ||
            captured_cartridge_address != 15'h1234 ||
            captured_cartridge_data != 8'h5a || cartridge_data != 8'h5a)
            $fatal(1, "cartridge data port was not published");
        repeat (2) @(posedge clock); #1;
        if (cartridge_cpu_data !== 8'h5a)
            $fatal(1, "cartridge RAM wrote %h at selected address, expected 5a",
                   cartridge_cpu_data);
        expected_cartridge_signature = 32'h0012345a;
        read32(32'h80000268, value);
        if (value !== expected_cartridge_signature)
            $fatal(1, "cartridge signature mismatch: %h", value);
        write32(32'h80000264, 32'h3);
        if (!cartridge_enabled || !saw_cartridge_launch)
            $fatal(1, "cartridge enable/launch was not retained");
        @(posedge clock);
        if (!cartridge_enabled)
            $fatal(1, "cartridge enable did not persist or launch did not pulse");
        $display("checking DECB BIN byte FIFO and loader completion");
        write32(32'h80000270, 32'h00000003); // reset and activate
        write32(32'h8000026c, 32'h000000a5);
        write32(32'h8000026c, 32'h000000b6);
        if (!bin_fifo_available || !bin_transfer_active ||
            bin_fifo_data !== 8'ha5)
            $fatal(1, "BIN FIFO did not publish its first byte");
        bin_fifo_pop = 1'b1;
        @(posedge clock); #1; bin_fifo_pop = 1'b0;
        if (!bin_fifo_available || bin_fifo_data !== 8'hb6)
            $fatal(1, "BIN FIFO pop did not advance to the second byte");
        write32(32'h80000270, 32'h00000004); // producer complete
        if (!bin_transfer_complete || bin_transfer_active || bin_transfer_error)
            $fatal(1, "BIN transfer completion flags are incorrect");
        bin_loader_done = 1'b1;
        @(posedge clock); #1; bin_loader_done = 1'b0;
        read32(32'h80000274, value);
        if (!value[16] || cartridge_enabled)
            $fatal(1, "BIN loader completion did not retire the cartridge");
        $display("configuring SPI");
        write32(32'h80000100, 32'h00000200); // active CS, divider=2
        rising_edges = 0;
        $display("starting transfer");
        write32(32'h80000104, 32'ha5);
        if (rising_edges != 8) $fatal(1, "SPI store ACK arrived after %0d rising edges, expected 8", rising_edges);
        read32(32'h80000108, value);
        if (value[7:0] != 8'hff) $fatal(1, "SPI receive mismatch: %h", value[7:0]);
        if (sd_cs_n !== 1'b0) $fatal(1, "SPI CS changed during transfer");
        $display("checking FDC sector publication barrier");
        fdc_request_toggle = 1;
        write32(32'h80000208, 0);
        for (rising_edges=0; rising_edges<256; rising_edges=rising_edges+1)
            write32(32'h8000020c, rising_edges[7:0] ^ 8'ha5);
        write32(32'h80000210, 1);
        if (fdc_done_toggle !== 1'b0)
            $fatal(1, "FDC sector published before barrier delay");
        repeat (4) @(posedge clock);
        if (fdc_done_toggle !== 1'b1 || fdc_success !== 1'b1)
            $fatal(1, "FDC complete sector was not published");
        fdc_buffer_address = 0;
        #1;
        if (fdc_buffer_data !== 8'ha5)
            $fatal(1, "FDC published bank byte 0 is %h, expected a5", fdc_buffer_data);
        fdc_buffer_address = 8'hff;
        #1;
        if (fdc_buffer_data !== 8'h5a)
            $fatal(1, "FDC published bank byte 255 is %h, expected 5a", fdc_buffer_data);
        fdc_request_toggle = 0;
        write32(32'h80000208, 0);
        write32(32'h8000020c, 8'haa);
        write32(32'h80000210, 1);
        repeat (4) @(posedge clock);
        if (fdc_done_toggle !== 1'b0 || fdc_success !== 1'b0)
            $fatal(1, "FDC incomplete sector was accepted");
        $display("checking full drive-0 disk cache");
        write32(32'h80000230, 0);
        for (rising_edges=0; rising_edges<512; rising_edges=rising_edges+1)
            write32(32'h80000234, rising_edges[7:0] ^ 8'h3c);
        write32(32'h80000238, 1);
        read32(32'h8000023c, value);
        if (value[0] !== 1'b1)
            $fatal(1, "drive-0 disk cache did not commit");
        write32(32'h80000244, 0);
        read32(32'h80000248, value);
        if (value[7:0] !== 8'h3c)
            $fatal(1, "boot-time cache readback is %h, expected 3c", value[7:0]);
        write32(32'h80000214, 32'h00000101);
        // A newly mounted full-disk cache starts with no demand-paged sector
        // in the small buffer.  Its FDC acknowledgement must nevertheless
        // succeed; the former startup audit accidentally hid this case by
        // leaving fdc_buffer_fill_count at 256.
        fdc_request_toggle = 1;
        write32(32'h80000210, 1);
        repeat (4) @(posedge clock);
        if (fdc_done_toggle !== 1'b1 || fdc_success !== 1'b1)
            $fatal(1, "newly mounted drive-0 full cache was not acknowledged");
        fdc_buffer_address = 8'h00;
        repeat (2) @(posedge clock); #1;
        if (fdc_buffer_data !== 8'h3c)
            $fatal(1, "drive-0 cache byte 0 is %h, expected 3c", fdc_buffer_data);
        fdc_buffer_address = 8'hff;
        repeat (2) @(posedge clock); #1;
        if (fdc_buffer_data !== 8'hc3)
            $fatal(1, "drive-0 cache byte 255 is %h, expected c3", fdc_buffer_data);
        fdc_buffer_address = 8'h05;
        fdc_write_data = 8'h77;
        fdc_write_strobe = 1;
        @(posedge clock); #1; fdc_write_strobe = 0;
        repeat (2) @(posedge clock); #1;
        if (fdc_buffer_data !== 8'h77)
            $fatal(1, "drive-0 write-through byte is %h, expected 77", fdc_buffer_data);
        $display("PASS: manager OSD, SPI, sector banks, and drive-0 full cache");
        $finish;
    end
endmodule
`default_nettype wire
