`timescale 1ns/1ps
`default_nettype none

// Wukong-owned integration of the unmodified hdl-util/hdmi packet and channel
// modules with the board's proven raster timing and OSERDESE2 serializer.
module wukong_hdmi_tx (
    input  wire       pixel_clk,
    input  wire       serial_clk,
    input  wire       reset,
    input  wire       hsync,
    input  wire       vsync,
    input  wire       video_enable,
    input  wire [7:0] red,
    input  wire [7:0] green,
    input  wire [7:0] blue,
    input  wire [5:0] audio_dac,
    output wire  [3:0] tmds_serial
);
    localparam int H_ACTIVE = 640;
    localparam int H_TOTAL = 800;
    localparam int V_ACTIVE = 480;
    localparam int V_TOTAL = 525;
    localparam int AUDIO_RATE = 48000;
    localparam int NUM_PACKETS = 4;

    logic [9:0] cx = 0;
    logic [9:0] cy = 0;
    logic previous_video_enable = 0;
    always_ff @(posedge pixel_clk) begin
        if (reset) begin
            cx <= 0;
            cy <= 0;
            previous_video_enable <= 0;
        end else if (video_enable && !previous_video_enable) begin
            // Artifact and CRT stages delay the source raster. Lock packet
            // placement to the observed active-line edge rather than assuming
            // that their delayed timing still has reset phase zero.
            cx <= 0;
            previous_video_enable <= video_enable;
        end else if (cx == H_TOTAL - 1) begin
            cx <= 0;
            cy <= cy == V_TOTAL - 1 ? 0 : cy + 1'b1;
            previous_video_enable <= video_enable;
        end else begin
            cx <= cx + 1'b1;
            previous_video_enable <= video_enable;
        end
    end

    // Numerically controlled 48 kHz sample clock from the exact 25 MHz pixel
    // clock. It toggles at 96 kHz, producing exactly 48,000 rising edges per
    // second on average while individual half-periods differ by one clock.
    logic [24:0] audio_phase = 0;
    logic audio_clk = 0;
    always_ff @(posedge pixel_clk) begin
        if (reset) begin
            audio_phase <= 0;
            audio_clk <= 0;
        end else if (audio_phase + 25'd96000 >= 25'd25000000) begin
            audio_phase <= audio_phase + 25'd96000 - 25'd25000000;
            audio_clk <= ~audio_clk;
        end else begin
            audio_phase <= audio_phase + 25'd96000;
        end
    end

    logic signed [6:0] centered_dac;
    logic signed [15:0] pcm_sample;
    logic [15:0] audio_samples [1:0];
    always_comb begin
        centered_dac = $signed({1'b0, audio_dac}) - 7'sd32;
        pcm_sample = centered_dac <<< 8; // quarter-scale output
        audio_samples[0] = pcm_sample;
        audio_samples[1] = pcm_sample;
    end

    logic video_guard;
    logic video_preamble;
    logic data_island_guard;
    logic data_island_preamble;
    logic data_island_period;
    logic data_island_instant;
    logic packet_enable;

    assign data_island_instant = cx >= H_ACTIVE + 14 &&
                                 cx < H_ACTIVE + 14 + NUM_PACKETS * 32;
    assign packet_enable = data_island_instant &&
                           ((cx + H_ACTIVE + 18) & 10'h01f) == 0;

    always_ff @(posedge pixel_clk) begin
        if (reset) begin
            video_guard <= 0;
            video_preamble <= 0;
            data_island_guard <= 0;
            data_island_preamble <= 0;
            data_island_period <= 0;
        end else begin
            video_guard <= cx >= H_TOTAL - 2 &&
                           (cy == V_TOTAL - 1 || cy < V_ACTIVE - 1);
            video_preamble <= cx >= H_TOTAL - 10 && cx < H_TOTAL - 2 &&
                              (cy == V_TOTAL - 1 || cy < V_ACTIVE - 1);
            data_island_guard <= (cx >= H_ACTIVE + 12 && cx < H_ACTIVE + 14) ||
                (cx >= H_ACTIVE + 14 + NUM_PACKETS * 32 &&
                 cx < H_ACTIVE + 16 + NUM_PACKETS * 32);
            data_island_preamble <= cx >= H_ACTIVE + 4 && cx < H_ACTIVE + 12;
            data_island_period <= data_island_instant;
        end
    end

    logic [23:0] header;
    logic [55:0] sub [3:0];
    logic [4:0] packet_pixel_counter;
    logic [8:0] packet_data;
    wire video_field_end = cx == H_ACTIVE - 1 && cy == V_ACTIVE - 1;

    packet_picker #(
        .VIDEO_ID_CODE(1), .VIDEO_RATE(25.0E6), .IT_CONTENT(1'b1),
        .AUDIO_RATE(AUDIO_RATE), .AUDIO_BIT_WIDTH(16),
        .VENDOR_NAME({"CoCoFPGA"}),
        .PRODUCT_DESCRIPTION({"Wukong CoCo3", 32'd0}),
        .SOURCE_DEVICE_INFORMATION(8'h08)
    ) packet_picker_i (
        .clk_pixel(pixel_clk), .clk_audio(audio_clk), .reset(reset),
        .video_field_end(video_field_end), .packet_enable(packet_enable),
        .packet_pixel_counter(packet_pixel_counter),
        .audio_sample_word(audio_samples), .header(header), .sub(sub)
    );

    packet_assembler packet_assembler_i (
        .clk_pixel(pixel_clk), .reset(reset),
        .data_island_period(data_island_period),
        .header(header), .sub(sub), .packet_data(packet_data),
        .counter(packet_pixel_counter)
    );

    logic [2:0] mode;
    logic [23:0] video_data;
    logic [5:0] control_data;
    logic [11:0] data_island_data;
    always_ff @(posedge pixel_clk) begin
        if (reset) begin
            mode <= 3'd0;
            video_data <= 0;
            control_data <= 0;
            data_island_data <= 0;
        end else begin
            mode <= data_island_guard ? 3'd4 :
                    data_island_period ? 3'd3 :
                    video_guard ? 3'd2 :
                    video_enable ? 3'd1 : 3'd0;
            video_data <= {red, green, blue};
            control_data <= {{1'b0, data_island_preamble},
                             {1'b0, video_preamble || data_island_preamble},
                             {vsync, hsync}};
            data_island_data[11:4] <= packet_data[8:1];
            data_island_data[3] <= cx != 0;
            data_island_data[2] <= packet_data[0];
            data_island_data[1:0] <= {vsync, hsync};
        end
    end

    wire [9:0] symbols [2:0];
    genvar channel;
    generate
        for (channel = 0; channel < 3; channel = channel + 1) begin : channels
            tmds_channel #(.CN(channel)) channel_i (
                .clk_pixel(pixel_clk),
                .video_data(video_data[channel*8 +: 8]),
                .data_island_data(data_island_data[channel*4 +: 4]),
                .control_data(control_data[channel*2 +: 2]),
                .mode(mode), .tmds(symbols[channel])
            );
        end
    endgenerate

    wire [9:0] clock_symbol = 10'b1111100000;
    tmds_serializer blue_serializer_i (
        .pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset),
        .parallel_data(symbols[0]), .serial_data(tmds_serial[0]));
    tmds_serializer green_serializer_i (
        .pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset),
        .parallel_data(symbols[1]), .serial_data(tmds_serial[1]));
    tmds_serializer red_serializer_i (
        .pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset),
        .parallel_data(symbols[2]), .serial_data(tmds_serial[2]));
    tmds_serializer clock_serializer_i (
        .pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset),
        .parallel_data(clock_symbol), .serial_data(tmds_serial[3]));
endmodule

`default_nettype wire
