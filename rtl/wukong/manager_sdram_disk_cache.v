`timescale 1ns/1ps
`default_nettype none

// Wukong W9825G6KH SDR SDRAM cache for one 161,280-byte DECB disk image.
//
// The management processor writes the image a byte at a time while mounting.
// FDC reads never depend directly on SDRAM latency: each requested 256-byte
// sector is streamed into a small distributed-RAM buffer before the manager
// acknowledges the WD1773 request.  The CoCo then reads that stable buffer at
// its normal bus cadence.  FDC writes update SDRAM through the same queued
// byte-write path while firmware separately persists the sector to FAT32.
module manager_sdram_disk_cache #(
    parameter integer POWERUP_CLOCKS = 25200,
    parameter integer REFRESH_CLOCKS = 952,
    parameter integer WRITE_FIFO_LOG2 = 4
) (
    input  wire        memory_clock,
    input  wire        cache_clock,
    input  wire        reset,

    input  wire        cache_write,
    input  wire [17:0] cache_write_address,
    input  wire [7:0]  cache_write_data,

    input  wire        sector_request_toggle,
    input  wire [17:0] sector_base_address,
    input  wire [7:0]  sector_read_address,
    output wire [7:0]  sector_read_data,
    output reg         sector_done_toggle,
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

    // This buffer is written only while the FDC is waiting and remains stable
    // after sector_done_toggle changes.  An asynchronous read therefore gives
    // the existing WD1773 path its required direct byte-addressed behavior.
    (* ram_style = "distributed" *) reg [7:0] sector_buffer [0:255];
    assign sector_read_data = sector_buffer[sector_read_address];

    // Capture each cache-clock write as a toggle plus stable payload.  The
    // clocks are related 1:5 on Wukong, but the toggle handshake avoids relying
    // on phase alignment and the destination FIFO absorbs SDRAM refreshes.
    reg [17:0] source_write_address;
    reg [7:0] source_write_data;
    reg source_write_toggle;
    reg cache_write_previous;
    reg source_sector_toggle;
    reg [17:0] source_sector_base;

    always @(posedge cache_clock) begin
        if (reset) begin
            source_write_address <= 0;
            source_write_data <= 0;
            source_write_toggle <= 1'b0;
            cache_write_previous <= 1'b0;
            source_sector_toggle <= 1'b0;
            source_sector_base <= 0;
        end else begin
            cache_write_previous <= cache_write;
            if (cache_write && !cache_write_previous) begin
                source_write_address <= cache_write_address;
                source_write_data <= cache_write_data;
                source_write_toggle <= ~source_write_toggle;
            end
            if (sector_request_toggle != source_sector_toggle) begin
                source_sector_toggle <= sector_request_toggle;
                source_sector_base <= sector_base_address;
            end
        end
    end

    localparam integer WRITE_FIFO_DEPTH = (1 << WRITE_FIFO_LOG2);
    reg [17:0] write_fifo_address [0:WRITE_FIFO_DEPTH-1];
    reg [7:0] write_fifo_data [0:WRITE_FIFO_DEPTH-1];
    reg [WRITE_FIFO_LOG2-1:0] write_fifo_write_pointer;
    reg [WRITE_FIFO_LOG2-1:0] write_fifo_read_pointer;
    reg [WRITE_FIFO_LOG2:0] write_fifo_count;
    reg [7:0] write_fifo_high_water;
    reg [7:0] write_drop_count;

    (* ASYNC_REG = "TRUE" *) reg write_toggle_meta, write_toggle_sync;
    reg write_toggle_seen;
    (* ASYNC_REG = "TRUE" *) reg [17:0] write_address_meta, write_address_sync;
    (* ASYNC_REG = "TRUE" *) reg [7:0] write_data_meta, write_data_sync;
    (* ASYNC_REG = "TRUE" *) reg sector_toggle_meta, sector_toggle_sync;
    reg sector_toggle_seen;
    (* ASYNC_REG = "TRUE" *) reg [17:0] sector_base_meta, sector_base_sync;

    wire write_event = write_toggle_sync != write_toggle_seen;
    wire sector_event = sector_toggle_sync != sector_toggle_seen;
    wire write_fifo_empty = write_fifo_count == 0;
    wire write_fifo_full = write_fifo_count == WRITE_FIFO_DEPTH;

    localparam [4:0]
        STATE_POWERUP      = 5'd0,
        STATE_INIT_PRE     = 5'd1,
        STATE_INIT_REFRESH = 5'd2,
        STATE_INIT_MODE    = 5'd3,
        STATE_WAIT         = 5'd4,
        STATE_IDLE         = 5'd5,
        STATE_PREPARE      = 5'd6,
        STATE_PRECHARGE    = 5'd7,
        STATE_ACTIVATE     = 5'd8,
        STATE_ISSUE        = 5'd9,
        STATE_STREAM       = 5'd10,
        STATE_COMPLETE     = 5'd11,
        STATE_REFRESH_PRE  = 5'd12,
        STATE_REFRESH      = 5'd13;

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
    reg request_prefetch;
    wire [1:0] request_bank = request_word[10:9];
    wire [12:0] request_row = request_word[23:11];
    wire [8:0] request_column = request_word[8:0];

    reg prefetch_pending;
    reg [17:0] prefetch_base_address;
    reg prefetch_completion_toggle;
    reg [7:0] stream_issue_count;
    reg [7:0] stream_capture_count;
    reg [2:0] stream_valid_pipeline;

    wire refresh_due = ready && refresh_count == REFRESH_CLOCKS - 1;
    wire refresh_service = ready && state == STATE_REFRESH;
    wire write_fifo_pop = ready && state == STATE_IDLE &&
                          refresh_debt == 0 && !write_fifo_empty;
    wire write_fifo_push = write_event &&
                           (!write_fifo_full || write_fifo_pop);
    wire [17:0] write_fifo_head_address =
        write_fifo_address[write_fifo_read_pointer];
    wire [7:0] write_fifo_head_data =
        write_fifo_data[write_fifo_read_pointer];

    assign debug_status = {write_drop_count, write_fifo_high_water,
                           7'b0, prefetch_pending,
                           refresh_debt_max[3:0], refresh_debt};

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
            request_prefetch <= 1'b0;
            prefetch_pending <= 1'b0;
            prefetch_base_address <= 0;
            prefetch_completion_toggle <= 1'b0;
            sector_done_toggle <= 1'b0;
            stream_issue_count <= 0;
            stream_capture_count <= 0;
            stream_valid_pipeline <= 0;
            write_fifo_write_pointer <= 0;
            write_fifo_read_pointer <= 0;
            write_fifo_count <= 0;
            write_fifo_high_water <= 0;
            write_drop_count <= 0;
            write_toggle_meta <= 0;
            write_toggle_sync <= 0;
            write_toggle_seen <= 0;
            write_address_meta <= 0;
            write_address_sync <= 0;
            write_data_meta <= 0;
            write_data_sync <= 0;
            sector_toggle_meta <= 0;
            sector_toggle_sync <= 0;
            sector_toggle_seen <= 0;
            sector_base_meta <= 0;
            sector_base_sync <= 0;
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

            write_toggle_meta <= source_write_toggle;
            write_toggle_sync <= write_toggle_meta;
            write_address_meta <= source_write_address;
            write_address_sync <= write_address_meta;
            write_data_meta <= source_write_data;
            write_data_sync <= write_data_meta;
            sector_toggle_meta <= source_sector_toggle;
            sector_toggle_sync <= sector_toggle_meta;
            sector_base_meta <= source_sector_base;
            sector_base_sync <= sector_base_meta;

            if (write_event)
                write_toggle_seen <= write_toggle_sync;
            if (sector_event) begin
                sector_toggle_seen <= sector_toggle_sync;
                prefetch_base_address <= sector_base_sync;
                prefetch_completion_toggle <= sector_toggle_sync;
                prefetch_pending <= 1'b1;
            end

            if (write_fifo_push) begin
                write_fifo_address[write_fifo_write_pointer] <=
                    write_address_sync;
                write_fifo_data[write_fifo_write_pointer] <= write_data_sync;
                write_fifo_write_pointer <= write_fifo_write_pointer + 1'b1;
            end else if (write_event && write_drop_count != 8'hff) begin
                write_drop_count <= write_drop_count + 1'b1;
            end
            if (write_fifo_pop)
                write_fifo_read_pointer <= write_fifo_read_pointer + 1'b1;
            case ({write_fifo_push, write_fifo_pop})
                2'b10: begin
                    write_fifo_count <= write_fifo_count + 1'b1;
                    if (write_fifo_count + 1'b1 > write_fifo_high_water)
                        write_fifo_high_water <= write_fifo_count + 1'b1;
                end
                2'b01: write_fifo_count <= write_fifo_count - 1'b1;
                default: begin end
            endcase

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
                    end else begin
                        powerup_count <= powerup_count + 1'b1;
                    end
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
                    // BL1, sequential, CAS latency 2, single-location writes.
                    sdram_ras_n <= 1'b0;
                    sdram_cas_n <= 1'b0;
                    sdram_we_n <= 1'b0;
                    sdram_address <= 13'h220;
                    wait_count <= 8'd1;
                    wait_return_state <= STATE_COMPLETE;
                    request_prefetch <= 1'b0;
                    request_write <= 1'b0;
                    state <= STATE_WAIT;
                end
                STATE_WAIT: begin
                    if (wait_count == 0)
                        state <= wait_return_state;
                    else
                        wait_count <= wait_count - 1'b1;
                end
                STATE_IDLE: begin
                    if (refresh_debt != 0) begin
                        state <= STATE_REFRESH_PRE;
                    end else if (!write_fifo_empty) begin
                        request_word <= {7'b0,
                                         write_fifo_head_address[17:1]};
                        request_write_data <= {write_fifo_head_data,
                                               write_fifo_head_data};
                        request_dqm <= write_fifo_head_address[0]
                            ? 2'b01 : 2'b10;
                        request_write <= 1'b1;
                        request_prefetch <= 1'b0;
                        state <= STATE_PREPARE;
                    end else if (prefetch_pending) begin
                        request_word <= {7'b0,
                                         prefetch_base_address[17:1]};
                        request_write_data <= 0;
                        request_dqm <= 2'b00;
                        request_write <= 1'b0;
                        request_prefetch <= 1'b1;
                        prefetch_pending <= 1'b0;
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
                    end else if (request_prefetch) begin
                        stream_issue_count <= 8'd1;
                        stream_capture_count <= 0;
                        stream_valid_pipeline <= 3'b001;
                        state <= STATE_STREAM;
                    end else begin
                        state <= STATE_COMPLETE;
                    end
                end
                STATE_STREAM: begin
                    stream_valid_pipeline <=
                        {stream_valid_pipeline[1:0], 1'b0};
                    if (stream_issue_count < 8'd128) begin
                        sdram_bank <= request_bank;
                        sdram_address[8:0] <= request_column +
                            stream_issue_count;
                        sdram_address[10] <= 1'b0;
                        sdram_cas_n <= 1'b0;
                        stream_valid_pipeline[0] <= 1'b1;
                        stream_issue_count <= stream_issue_count + 1'b1;
                    end
                    if (stream_valid_pipeline[2]) begin
                        sector_buffer[{stream_capture_count[6:0], 1'b0}] <=
                            data_in[7:0];
                        sector_buffer[{stream_capture_count[6:0], 1'b1}] <=
                            data_in[15:8];
                        stream_capture_count <= stream_capture_count + 1'b1;
                        if (stream_capture_count == 8'd127) begin
                            sector_done_toggle <= prefetch_completion_toggle;
                            state <= STATE_COMPLETE;
                        end
                    end
                end
                STATE_COMPLETE: begin
                    if (!ready) begin
                        ready <= 1'b1;
                        refresh_count <= 0;
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
                    refresh_count <= 0;
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
