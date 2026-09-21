`timescale 1ns/1ps
`default_nettype none

// Hybrid 512 KiB CoCo 3 memory for Wukong.
//
// The compatibility-critical $30-$3f MMU pages occupy the existing 128 KiB
// dual-port block RAM.  That includes the reset map ($38-$3f), so BASIC and
// ordinary 64/128 KiB software retain the exact proven CPU/video timing.
// Pages $00-$2f are distinct SDRAM storage (384 KiB).  CPU accesses use a
// request/completion handshake and hold the 6809 until the byte is complete.
// GIME accesses cannot wait, so two 256-word buffers fetch aligned SDRAM
// regions with consecutive BL1 commands and serve video at pixel-clock speed.
module coco3_hybrid_512k_ram #(
    parameter integer POWERUP_CLOCKS = 25200,
    parameter integer REFRESH_CLOCKS = 952
) (
    input  wire        memory_clock,
    input  wire        video_clock,
    input  wire        reset,

    input  wire [18:0] cpu_address,
    input  wire [7:0]  cpu_write_data,
    input  wire        cpu_read_enable,
    input  wire        cpu_write_enable,
    output wire [7:0]  cpu_read_data,
    output wire        cpu_wait,

    input  wire [19:0] video_address,
    input  wire        video_blank,
    output wire [15:0] video_read_data,
    output reg         ready,
    output wire [31:0] debug_status,

    output wire        sdram_clk,
    output reg         sdram_cke,
    output reg         sdram_cs_n,
    output reg         sdram_ras_n,
    output reg         sdram_cas_n,
    output reg         sdram_we_n,
    output reg  [1:0]  sdram_dqm,
    output reg  [12:0] sdram_address,
    output reg  [1:0]  sdram_bank,
    inout  wire [15:0] sdram_data
);
    localparam [23:0] COCO_BASE_WORD = 24'h080000;

`ifdef SYNTHESIS
    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"), .INIT(1'b0), .SRTYPE("SYNC")
    ) sdram_clock_oddr_i (
        .C(memory_clock), .CE(1'b1), .D1(1'b0), .D2(1'b1),
        .Q(sdram_clk), .R(1'b0), .S(1'b0)
    );
`else
    assign sdram_clk = memory_clock;
`endif

    reg [15:0] data_out;
    reg data_output_enable;
    assign sdram_data = data_output_enable ? data_out : 16'hzzzz;
    wire [15:0] data_in = sdram_data;

    // Page numbers $30-$3f map one-to-one onto the old 128 KiB BRAM's
    // sixteen pages.  The choice is invisible to software and preserves the
    // real 512 KiB page numbers used by the GIME MMU.
    wire cpu_bram_select = cpu_address[18:17] == 2'b11;
    wire video_bram_select = video_address[17:16] == 2'b11;
    wire [7:0] bram_cpu_data;
    wire [15:0] bram_video_data;
    coco3_128k_ram #(.INIT_VALUE(8'h00)) bram_i (
        .clock(video_clock),
        .cpu_address(cpu_address[16:0]),
        .cpu_write_data(cpu_write_data),
        .cpu_write_enable(cpu_write_enable && cpu_bram_select),
        .cpu_read_data(bram_cpu_data),
        .video_address(video_address),
        .video_read_data(bram_video_data)
    );

    // CPU request handshake (25.2 MHz -> 126 MHz).  Payload remains stable
    // until the completion toggle returns.
    reg [18:0] cpu_request_address;
    reg [7:0] cpu_request_write_data;
    reg cpu_request_write;
    reg cpu_request_toggle;
    reg cpu_request_pending;
    reg cpu_write_previous;
    reg [7:0] upper_cpu_data;
    reg [18:0] upper_cpu_data_address;
    reg upper_cpu_data_valid;
    (* ASYNC_REG = "TRUE" *) reg cpu_done_meta, cpu_done_sync;
    reg cpu_done_seen;
    (* ASYNC_REG = "TRUE" *) reg [7:0] cpu_response_meta, cpu_response_sync;
    reg memory_cpu_done_toggle;
    reg [7:0] memory_cpu_read_data;
    reg memory_video_done_toggle;

    wire upper_cpu_read = cpu_read_enable && !cpu_bram_select;
    wire upper_cpu_read_hit = upper_cpu_data_valid &&
                              upper_cpu_data_address == cpu_address;
    assign cpu_read_data = cpu_bram_select ? bram_cpu_data : upper_cpu_data;
    assign cpu_wait = cpu_request_pending ||
                      (upper_cpu_read && !upper_cpu_read_hit);

    always @(posedge video_clock) begin
        if (reset) begin
            cpu_request_address <= 0;
            cpu_request_write_data <= 0;
            cpu_request_write <= 1'b0;
            cpu_request_toggle <= 1'b0;
            cpu_request_pending <= 1'b0;
            cpu_write_previous <= 1'b0;
            upper_cpu_data <= 0;
            upper_cpu_data_address <= 0;
            upper_cpu_data_valid <= 1'b0;
            cpu_done_meta <= 0;
            cpu_done_sync <= 0;
            cpu_done_seen <= 0;
            cpu_response_meta <= 0;
            cpu_response_sync <= 0;
        end else begin
            cpu_done_meta <= memory_cpu_done_toggle;
            cpu_done_sync <= cpu_done_meta;
            cpu_response_meta <= memory_cpu_read_data;
            cpu_response_sync <= cpu_response_meta;
            cpu_write_previous <= cpu_write_enable;

            if (cpu_request_pending && cpu_done_sync != cpu_done_seen) begin
                cpu_done_seen <= cpu_done_sync;
                cpu_request_pending <= 1'b0;
                if (!cpu_request_write) begin
                    upper_cpu_data <= cpu_response_sync;
                    upper_cpu_data_address <= cpu_request_address;
                    upper_cpu_data_valid <= 1'b1;
                end
            end

            if (!cpu_request_pending && ready) begin
                if (cpu_write_enable && !cpu_write_previous &&
                    !cpu_bram_select) begin
                    cpu_request_address <= cpu_address;
                    cpu_request_write_data <= cpu_write_data;
                    cpu_request_write <= 1'b1;
                    cpu_request_toggle <= ~cpu_request_toggle;
                    cpu_request_pending <= 1'b1;
                    if (upper_cpu_data_valid &&
                        upper_cpu_data_address == cpu_address)
                        upper_cpu_data_valid <= 1'b0;
                end else if (upper_cpu_read && !upper_cpu_read_hit) begin
                    cpu_request_address <= cpu_address;
                    cpu_request_write_data <= 0;
                    cpu_request_write <= 1'b0;
                    cpu_request_toggle <= ~cpu_request_toggle;
                    cpu_request_pending <= 1'b1;
                end
            end
        end
    end

    // Two SDRAM-backed line buffers. They use distributed RAM so the BRAM
    // footprint remains exactly the proven 128 KiB machine RAM plus existing
    // project memories. The memory controller writes; video reads async and
    // registers the selected word on the normal pixel-clock edge.
    (* ram_style = "distributed" *) reg [15:0] video_buffer0 [0:255];
    (* ram_style = "distributed" *) reg [15:0] video_buffer1 [0:255];
    reg [17:8] video_tag0, video_tag1;
    reg video_valid0, video_valid1;
    reg video_fill_buffer;
    reg [17:8] video_fill_tag;
    reg video_fill_pending;
    reg video_request_toggle;
    (* ASYNC_REG = "TRUE" *) reg video_done_meta, video_done_sync;
    reg video_done_seen;
    reg [15:0] upper_video_data;
    reg video_bram_select_q;

    wire video_hit0 = video_valid0 && video_tag0 == video_address[17:8];
    wire video_hit1 = video_valid1 && video_tag1 == video_address[17:8];
    wire video_hit = video_hit0 || video_hit1;
    wire video_selected_buffer = video_hit1;
    wire [15:0] selected_video_word = video_selected_buffer
        ? video_buffer1[video_address[7:0]]
        : video_buffer0[video_address[7:0]];
    wire [17:8] next_video_tag = video_address[17:8] + 1'b1;
    wire next_video_cached = (video_valid0 && video_tag0 == next_video_tag) ||
                             (video_valid1 && video_tag1 == next_video_tag);

    assign video_read_data = video_bram_select_q
        ? bram_video_data : upper_video_data;

    always @(posedge video_clock) begin
        if (reset) begin
            video_tag0 <= 0;
            video_tag1 <= 0;
            video_valid0 <= 1'b0;
            video_valid1 <= 1'b0;
            video_fill_buffer <= 1'b0;
            video_fill_tag <= 0;
            video_fill_pending <= 1'b0;
            video_request_toggle <= 1'b0;
            video_done_meta <= 0;
            video_done_sync <= 0;
            video_done_seen <= 0;
            upper_video_data <= 0;
            video_bram_select_q <= 1'b1;
        end else begin
            video_done_meta <= memory_video_done_toggle;
            video_done_sync <= video_done_meta;
            video_bram_select_q <= video_bram_select;
            if (!video_bram_select)
                upper_video_data <= video_hit ? selected_video_word : 16'h0000;

            if (video_fill_pending && video_done_sync != video_done_seen) begin
                video_done_seen <= video_done_sync;
                video_fill_pending <= 1'b0;
                if (video_fill_buffer) begin
                    video_tag1 <= video_fill_tag;
                    video_valid1 <= 1'b1;
                end else begin
                    video_tag0 <= video_fill_tag;
                    video_valid0 <= 1'b1;
                end
            end

            if (ready && !video_bram_select && !video_fill_pending) begin
                if (!video_hit) begin
                    video_fill_buffer <= video_valid0 &&
                        (!video_valid1 || video_tag0 == video_address[17:8]);
                    video_fill_tag <= video_address[17:8];
                    video_request_toggle <= ~video_request_toggle;
                    video_fill_pending <= 1'b1;
                end else if (!video_blank && video_address[7:0] >= 8'd192 &&
                             !next_video_cached) begin
                    video_fill_buffer <= video_hit0;
                    video_fill_tag <= next_video_tag;
                    video_request_toggle <= ~video_request_toggle;
                    video_fill_pending <= 1'b1;
                end
            end
        end
    end

    // Synchronize stable request payloads into the SDRAM clock domain.
    (* ASYNC_REG = "TRUE" *) reg cpu_toggle_meta, cpu_toggle_sync;
    reg cpu_toggle_seen;
    (* ASYNC_REG = "TRUE" *) reg [18:0] cpu_address_meta, cpu_address_sync;
    (* ASYNC_REG = "TRUE" *) reg [7:0] cpu_data_meta, cpu_data_sync;
    (* ASYNC_REG = "TRUE" *) reg cpu_write_meta, cpu_write_sync;
    (* ASYNC_REG = "TRUE" *) reg video_toggle_meta, video_toggle_sync;
    reg video_toggle_seen;
    (* ASYNC_REG = "TRUE" *) reg [9:0] video_tag_meta, video_tag_sync;
    (* ASYNC_REG = "TRUE" *) reg video_buffer_meta, video_buffer_sync;

    reg memory_cpu_pending;
    reg [18:0] memory_cpu_address;
    reg [7:0] memory_cpu_write_data;
    reg memory_cpu_write;
    reg memory_video_pending;
    reg [17:8] memory_video_tag;
    reg memory_video_buffer;
    reg [17:8] memory_video_tag0, memory_video_tag1;
    reg memory_video_valid0, memory_video_valid1;

    localparam [4:0]
        STATE_POWERUP       = 5'd0,
        STATE_INIT_PRE      = 5'd1,
        STATE_INIT_REFRESH  = 5'd2,
        STATE_INIT_MODE     = 5'd3,
        STATE_WAIT          = 5'd4,
        STATE_IDLE          = 5'd5,
        STATE_PREPARE       = 5'd6,
        STATE_PRECHARGE     = 5'd7,
        STATE_ACTIVATE      = 5'd8,
        STATE_ISSUE         = 5'd9,
        STATE_CAPTURE       = 5'd10,
        STATE_STREAM        = 5'd11,
        STATE_COMPLETE      = 5'd12,
        STATE_REFRESH_PRE   = 5'd13,
        STATE_REFRESH       = 5'd14;
    localparam [1:0] OWNER_CPU = 2'd0, OWNER_VIDEO = 2'd1;

    reg [4:0] state, wait_return_state;
    reg [7:0] wait_count;
    reg [15:0] powerup_count;
    reg [3:0] init_refresh_count;
    reg [19:0] refresh_count;
    reg [3:0] refresh_debt;
    reg [7:0] refresh_debt_max;
    reg [3:0] open_valid;
    reg [12:0] open_row [0:3];
    reg [23:0] request_word;
    reg [15:0] request_write_data;
    reg [1:0] request_dqm;
    reg request_write;
    reg [1:0] request_owner;
    reg request_cpu_lane;
    reg request_video_buffer;
    reg [8:0] stream_issue_count;
    reg [8:0] stream_capture_count;
    reg [2:0] stream_valid_pipeline;
    reg [7:0] stream_index_pipeline [0:2];

    wire [1:0] request_bank = request_word[10:9];
    wire [12:0] request_row = request_word[23:11];
    wire [8:0] request_column = request_word[8:0];
    wire refresh_due = ready && refresh_count == REFRESH_CLOCKS - 1;
    wire refresh_service = ready && state == STATE_REFRESH;
    wire refresh_priority = refresh_debt != 0 &&
                            (!memory_video_pending || refresh_debt == 4'hf);
    reg [7:0] cpu_wait_count_max;
    reg [7:0] cpu_wait_count;
    reg [7:0] video_fill_count;
    assign debug_status = {cpu_wait_count_max, video_fill_count,
                           refresh_debt_max, 4'b0, refresh_debt};

    integer bank_index;
    always @(posedge memory_clock) begin
        if (reset) begin
            state <= STATE_POWERUP;
            wait_return_state <= STATE_POWERUP;
            wait_count <= 0;
            powerup_count <= 0;
            init_refresh_count <= 0;
            refresh_count <= 0;
            refresh_debt <= 0;
            refresh_debt_max <= 0;
            open_valid <= 0;
            for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1)
                open_row[bank_index] <= 0;
            request_word <= 0;
            request_write_data <= 0;
            request_dqm <= 2'b11;
            request_write <= 1'b0;
            request_owner <= OWNER_CPU;
            request_cpu_lane <= 1'b0;
            request_video_buffer <= 1'b0;
            stream_issue_count <= 0;
            stream_capture_count <= 0;
            stream_valid_pipeline <= 0;
            for (bank_index = 0; bank_index < 3; bank_index = bank_index + 1)
                stream_index_pipeline[bank_index] <= 0;
            cpu_toggle_meta <= 0;
            cpu_toggle_sync <= 0;
            cpu_toggle_seen <= 0;
            cpu_address_meta <= 0;
            cpu_address_sync <= 0;
            cpu_data_meta <= 0;
            cpu_data_sync <= 0;
            cpu_write_meta <= 0;
            cpu_write_sync <= 0;
            video_toggle_meta <= 0;
            video_toggle_sync <= 0;
            video_toggle_seen <= 0;
            video_tag_meta <= 0;
            video_tag_sync <= 0;
            video_buffer_meta <= 0;
            video_buffer_sync <= 0;
            memory_cpu_pending <= 1'b0;
            memory_cpu_address <= 0;
            memory_cpu_write_data <= 0;
            memory_cpu_write <= 1'b0;
            memory_cpu_done_toggle <= 1'b0;
            memory_cpu_read_data <= 0;
            memory_video_pending <= 1'b0;
            memory_video_tag <= 0;
            memory_video_buffer <= 0;
            memory_video_tag0 <= 0;
            memory_video_tag1 <= 0;
            memory_video_valid0 <= 1'b0;
            memory_video_valid1 <= 1'b0;
            memory_video_done_toggle <= 1'b0;
            cpu_wait_count_max <= 0;
            cpu_wait_count <= 0;
            video_fill_count <= 0;
            ready <= 1'b0;
            sdram_cke <= 1'b0;
            sdram_cs_n <= 1'b1;
            sdram_ras_n <= 1'b1;
            sdram_cas_n <= 1'b1;
            sdram_we_n <= 1'b1;
            sdram_dqm <= 2'b11;
            sdram_address <= 0;
            sdram_bank <= 0;
            data_out <= 0;
            data_output_enable <= 1'b0;
        end else begin
            sdram_cs_n <= 1'b0;
            sdram_ras_n <= 1'b1;
            sdram_cas_n <= 1'b1;
            sdram_we_n <= 1'b1;
            sdram_dqm <= 2'b00;
            sdram_address <= 0;
            sdram_bank <= 0;
            data_output_enable <= 1'b0;

            cpu_toggle_meta <= cpu_request_toggle;
            cpu_toggle_sync <= cpu_toggle_meta;
            cpu_address_meta <= cpu_request_address;
            cpu_address_sync <= cpu_address_meta;
            cpu_data_meta <= cpu_request_write_data;
            cpu_data_sync <= cpu_data_meta;
            cpu_write_meta <= cpu_request_write;
            cpu_write_sync <= cpu_write_meta;
            video_toggle_meta <= video_request_toggle;
            video_toggle_sync <= video_toggle_meta;
            video_tag_meta <= video_fill_tag;
            video_tag_sync <= video_tag_meta;
            video_buffer_meta <= video_fill_buffer;
            video_buffer_sync <= video_buffer_meta;

            if (cpu_toggle_sync != cpu_toggle_seen && !memory_cpu_pending) begin
                cpu_toggle_seen <= cpu_toggle_sync;
                memory_cpu_address <= cpu_address_sync;
                memory_cpu_write_data <= cpu_data_sync;
                memory_cpu_write <= cpu_write_sync;
                memory_cpu_pending <= 1'b1;
                cpu_wait_count <= 0;
            end else if (memory_cpu_pending && cpu_wait_count != 8'hff) begin
                cpu_wait_count <= cpu_wait_count + 1'b1;
            end
            if (video_toggle_sync != video_toggle_seen &&
                !memory_video_pending) begin
                video_toggle_seen <= video_toggle_sync;
                memory_video_tag <= video_tag_sync;
                memory_video_buffer <= video_buffer_sync;
                memory_video_pending <= 1'b1;
            end

            if (ready) begin
                if (refresh_due)
                    refresh_count <= 0;
                else
                    refresh_count <= refresh_count + 1'b1;
            end
            case ({refresh_due, refresh_service})
                2'b10: if (refresh_debt != 4'hf)
                    refresh_debt <= refresh_debt + 1'b1;
                2'b01: if (refresh_debt != 0)
                    refresh_debt <= refresh_debt - 1'b1;
                default: begin end
            endcase
            if (refresh_due && !refresh_service && refresh_debt != 4'hf &&
                refresh_debt + 1'b1 > refresh_debt_max)
                refresh_debt_max <= refresh_debt + 1'b1;

            case (state)
                STATE_POWERUP: begin
                    sdram_cke <= 1'b0;
                    sdram_cs_n <= 1'b1;
                    sdram_dqm <= 2'b11;
                    if (powerup_count == POWERUP_CLOCKS - 1) begin
                        powerup_count <= 0;
                        sdram_cke <= 1'b1;
                        state <= STATE_INIT_PRE;
                    end else powerup_count <= powerup_count + 1'b1;
                end
                STATE_INIT_PRE: begin
                    sdram_ras_n <= 1'b0;
                    sdram_we_n <= 1'b0;
                    sdram_address[10] <= 1'b1;
                    open_valid <= 0;
                    wait_count <= 8'd2;
                    wait_return_state <= STATE_INIT_REFRESH;
                    state <= STATE_WAIT;
                end
                STATE_INIT_REFRESH: begin
                    sdram_ras_n <= 1'b0;
                    sdram_cas_n <= 1'b0;
                    init_refresh_count <= init_refresh_count + 1'b1;
                    wait_count <= 8'd7;
                    wait_return_state <= init_refresh_count == 4'd7
                        ? STATE_INIT_MODE : STATE_INIT_REFRESH;
                    state <= STATE_WAIT;
                end
                STATE_INIT_MODE: begin
                    sdram_ras_n <= 1'b0;
                    sdram_cas_n <= 1'b0;
                    sdram_we_n <= 1'b0;
                    sdram_address <= 13'h220; // BL1, CAS2, sequential
                    wait_count <= 8'd1;
                    wait_return_state <= STATE_COMPLETE;
                    request_owner <= OWNER_CPU;
                    state <= STATE_WAIT;
                end
                STATE_WAIT: begin
                    if (wait_count == 0)
                        state <= wait_return_state;
                    else
                        wait_count <= wait_count - 1'b1;
                end
                STATE_IDLE: begin
                    if (refresh_priority) begin
                        state <= STATE_REFRESH_PRE;
                    end else if (memory_video_pending) begin
                        request_word <= COCO_BASE_WORD +
                            {6'b0, memory_video_tag, 8'b0};
                        request_write_data <= 0;
                        request_dqm <= 2'b00;
                        request_write <= 1'b0;
                        request_owner <= OWNER_VIDEO;
                        request_video_buffer <= memory_video_buffer;
                        memory_video_pending <= 1'b0;
                        state <= STATE_PREPARE;
                    end else if (memory_cpu_pending) begin
                        request_word <= COCO_BASE_WORD +
                            {6'b0, memory_cpu_address[18:1]};
                        request_write_data <= {memory_cpu_write_data,
                                               memory_cpu_write_data};
                        request_dqm <= memory_cpu_address[0]
                            ? 2'b01 : 2'b10;
                        request_write <= memory_cpu_write;
                        request_owner <= OWNER_CPU;
                        request_cpu_lane <= memory_cpu_address[0];
                        memory_cpu_pending <= 1'b0;
                        state <= STATE_PREPARE;
                    end
                end
                STATE_PREPARE: begin
                    if (open_valid[request_bank] &&
                        open_row[request_bank] != request_row)
                        state <= STATE_PRECHARGE;
                    else if (!open_valid[request_bank])
                        state <= STATE_ACTIVATE;
                    else
                        state <= STATE_ISSUE;
                end
                STATE_PRECHARGE: begin
                    sdram_ras_n <= 1'b0;
                    sdram_we_n <= 1'b0;
                    sdram_bank <= request_bank;
                    sdram_address[10] <= 1'b0;
                    open_valid[request_bank] <= 1'b0;
                    wait_count <= 8'd1;
                    wait_return_state <= STATE_ACTIVATE;
                    state <= STATE_WAIT;
                end
                STATE_ACTIVATE: begin
                    sdram_ras_n <= 1'b0;
                    sdram_bank <= request_bank;
                    sdram_address <= request_row;
                    open_valid[request_bank] <= 1'b1;
                    open_row[request_bank] <= request_row;
                    wait_count <= 8'd1;
                    wait_return_state <= STATE_ISSUE;
                    state <= STATE_WAIT;
                end
                STATE_ISSUE: begin
                    sdram_bank <= request_bank;
                    sdram_address[8:0] <= request_column;
                    sdram_address[10] <= 1'b0;
                    sdram_cas_n <= 1'b0;
                    sdram_dqm <= request_dqm;
                    if (request_write) begin
                        sdram_we_n <= 1'b0;
                        data_out <= request_write_data;
                        data_output_enable <= 1'b1;
                        wait_count <= 0;
                        wait_return_state <= STATE_COMPLETE;
                        state <= STATE_WAIT;
                    end else if (request_owner == OWNER_VIDEO) begin
                        stream_issue_count <= 9'd1;
                        stream_capture_count <= 0;
                        stream_valid_pipeline <= 3'b001;
                        stream_index_pipeline[0] <= 0;
                        stream_index_pipeline[1] <= 0;
                        stream_index_pipeline[2] <= 0;
                        state <= STATE_STREAM;
                    end else begin
                        wait_count <= 8'd1;
                        wait_return_state <= STATE_CAPTURE;
                        state <= STATE_WAIT;
                    end
                end
                STATE_STREAM: begin
                    stream_valid_pipeline <=
                        {stream_valid_pipeline[1:0], 1'b0};
                    stream_index_pipeline[2] <= stream_index_pipeline[1];
                    stream_index_pipeline[1] <= stream_index_pipeline[0];
                    if (stream_issue_count < 9'd256) begin
                        sdram_bank <= request_bank;
                        sdram_address[8:0] <= request_column +
                            stream_issue_count;
                        sdram_address[10] <= 1'b0;
                        sdram_cas_n <= 1'b0;
                        stream_valid_pipeline[0] <= 1'b1;
                        stream_index_pipeline[0] <= stream_issue_count[7:0];
                        stream_issue_count <= stream_issue_count + 1'b1;
                    end
                    if (stream_valid_pipeline[2]) begin
                        if (request_video_buffer)
                            video_buffer1[stream_index_pipeline[2]] <= data_in;
                        else
                            video_buffer0[stream_index_pipeline[2]] <= data_in;
                        stream_capture_count <= stream_capture_count + 1'b1;
                        if (stream_capture_count == 9'd255)
                            state <= STATE_COMPLETE;
                    end
                end
                STATE_CAPTURE: begin
                    memory_cpu_read_data <= request_cpu_lane
                        ? data_in[15:8] : data_in[7:0];
                    state <= STATE_COMPLETE;
                end
                STATE_COMPLETE: begin
                    if (!ready) begin
                        ready <= 1'b1;
                        refresh_count <= 0;
                    end else if (request_owner == OWNER_VIDEO) begin
                        if (request_video_buffer) begin
                            memory_video_tag1 <= request_word[17:8] -
                                                 COCO_BASE_WORD[17:8];
                            memory_video_valid1 <= 1'b1;
                        end else begin
                            memory_video_tag0 <= request_word[17:8] -
                                                 COCO_BASE_WORD[17:8];
                            memory_video_valid0 <= 1'b1;
                        end
                        memory_video_done_toggle <= ~memory_video_done_toggle;
                        if (video_fill_count != 8'hff)
                            video_fill_count <= video_fill_count + 1'b1;
                    end else begin
                        // Keep a displayed upper-memory line coherent without
                        // refetching all 512 bytes after every CPU pixel write.
                        if (request_write && memory_video_valid0 &&
                            memory_video_tag0 == memory_cpu_address[18:9]) begin
                            if (memory_cpu_address[0])
                                video_buffer0[memory_cpu_address[8:1]][15:8]
                                    <= memory_cpu_write_data;
                            else
                                video_buffer0[memory_cpu_address[8:1]][7:0]
                                    <= memory_cpu_write_data;
                        end
                        if (request_write && memory_video_valid1 &&
                            memory_video_tag1 == memory_cpu_address[18:9]) begin
                            if (memory_cpu_address[0])
                                video_buffer1[memory_cpu_address[8:1]][15:8]
                                    <= memory_cpu_write_data;
                            else
                                video_buffer1[memory_cpu_address[8:1]][7:0]
                                    <= memory_cpu_write_data;
                        end
                        memory_cpu_done_toggle <= ~memory_cpu_done_toggle;
                        if (cpu_wait_count > cpu_wait_count_max)
                            cpu_wait_count_max <= cpu_wait_count;
                    end
                    state <= STATE_IDLE;
                end
                STATE_REFRESH_PRE: begin
                    sdram_ras_n <= 1'b0;
                    sdram_we_n <= 1'b0;
                    sdram_address[10] <= 1'b1;
                    open_valid <= 0;
                    wait_count <= 8'd1;
                    wait_return_state <= STATE_REFRESH;
                    state <= STATE_WAIT;
                end
                STATE_REFRESH: begin
                    sdram_ras_n <= 1'b0;
                    sdram_cas_n <= 1'b0;
                    wait_count <= 8'd7;
                    wait_return_state <= STATE_IDLE;
                    state <= STATE_WAIT;
                end
                default: state <= STATE_POWERUP;
            endcase
        end
    end
endmodule

`default_nettype wire
