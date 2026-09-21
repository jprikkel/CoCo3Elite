`timescale 1ns/1ps
`default_nettype none

// Wukong V3 W9825G6KH-6 SDR SDRAM backend for the CoCo memory bus.
//
// The CoCo/GIME side remains in the 25.2 MHz pixel-clock domain.  The SDRAM
// controller runs from the synchronous 126 MHz serializer clock (exactly 5x
// the 25.2 MHz pixel clock) with CAS latency two. This baseline controller uses
// single-word SDRAM writes.  This diagnostic configuration keeps SDRAM as the
// CPU backing store while a write-through dual-clock BRAM shadow supplies the
// GIME.  It deliberately trades BRAM for deterministic video timing so SDRAM
// CPU correctness can be tested independently of video arbitration.
//
// This first hardware milestone deliberately exposes exactly 128 KiB.  The
// wider SDRAM addressing is retained internally so later 512 KiB and 2 MiB
// configurations only need wider CoCo physical addresses and a larger boot
// clear limit; the SDRAM command engine does not change.
module coco3_sdram_ram #(
    parameter integer POWERUP_CLOCKS = 25200,
    parameter integer CLEAR_WORDS = 65536,
    parameter integer REFRESH_CLOCKS = 952,
    parameter integer WRITE_FIFO_LOG2 = 4
) (
    input  wire        memory_clock,
    input  wire        video_clock,
    input  wire        reset,

    input  wire [16:0] cpu_address,
    input  wire [7:0]  cpu_write_data,
    input  wire        cpu_read_enable,
    input  wire        cpu_write_enable,
    output reg  [7:0]  cpu_read_data,

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
    // Forward an inverted copy of the controller clock. Commands and write
    // data change on memory_clock's rising edge and are therefore stable for
    // half a cycle before the SDRAM samples its rising edge.
`ifdef SYNTHESIS
    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
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

    // Temporary 128 KiB write-through video shadow.  CPU writes update both
    // SDRAM and this mirror; the GIME reads the mirror in its native clock
    // domain with the same one-clock behavior as coco3_128k_ram.
    (* ram_style = "block" *) reg [7:0] video_shadow_low [0:65535];
    (* ram_style = "block" *) reg [7:0] video_shadow_high [0:65535];
    reg [15:0] video_shadow_read_data;
    reg [15:0] video_sdram_read_data;
    assign video_read_data = video_shadow_read_data;
    integer video_shadow_index;

    initial begin
        for (video_shadow_index = 0; video_shadow_index < 65536;
             video_shadow_index = video_shadow_index + 1) begin
            video_shadow_low[video_shadow_index] = 8'h00;
            video_shadow_high[video_shadow_index] = 8'h00;
        end
    end

    always @(posedge video_clock) begin
        video_shadow_read_data[7:0] <=
            video_shadow_low[video_address[15:0]];
        video_shadow_read_data[15:8] <=
            video_shadow_high[video_address[15:0]];
    end

    localparam [4:0]
        STATE_POWERUP       = 5'd0,
        STATE_INIT_PRE      = 5'd1,
        STATE_INIT_REFRESH  = 5'd2,
        STATE_INIT_MODE     = 5'd3,
        STATE_WAIT          = 5'd4,
        STATE_CLEAR_SELECT  = 5'd5,
        STATE_IDLE          = 5'd6,
        STATE_PREPARE       = 5'd7,
        STATE_PRECHARGE     = 5'd8,
        STATE_ACTIVATE      = 5'd9,
        STATE_ISSUE         = 5'd10,
        STATE_CAPTURE       = 5'd11,
        STATE_COMPLETE      = 5'd12,
        STATE_REFRESH_PRE   = 5'd13,
        STATE_REFRESH       = 5'd14,
        STATE_VIDEO_STREAM  = 5'd15;

    localparam [1:0]
        OWNER_CLEAR = 2'd0,
        OWNER_VIDEO = 2'd1,
        OWNER_CPU_READ = 2'd2,
        OWNER_CPU_WRITE = 2'd3;

    reg [4:0] state;
    reg [4:0] wait_return_state;
    reg [7:0] wait_count;
    reg [15:0] powerup_count;
    reg [3:0] init_refresh_count;
    reg [19:0] refresh_count;
    reg [3:0] refresh_debt;
    reg [7:0] refresh_debt_max;

    reg [23:0] clear_word;
    reg [23:0] request_word;
    reg [15:0] request_write_data;
    reg [1:0] request_dqm;
    reg request_write;
    reg [1:0] request_owner;
    reg request_cpu_lane;

    reg [3:0] open_valid;
    reg [12:0] open_row [0:3];
    wire [1:0] request_bank = request_word[10:9];
    wire [12:0] request_row = request_word[23:11];
    wire [8:0] request_column = request_word[8:0];

    reg [19:0] video_observed_address;
    reg video_observed_valid;
    reg [19:0] video_address_sampled;
    reg video_blank_sampled;
    reg [19:0] video_pending_address;
    reg video_pending;
    reg [19:0] video_input_address_previous;
    reg video_input_address_valid;
    reg [15:0] video_result_address;
    reg video_result_valid;
    reg [7:0] video_deadline_miss_count;

    // Eight entries retain the current four-word display group and the next
    // prefetched group. The low address bits select an entry and the complete
    // implemented word address is retained as a tag, so jumps and wrapping
    // display addresses cannot return an unrelated cached word.
    reg [7:0] video_cache_valid;
    reg [15:0] video_cache_address [0:7];
    reg [15:0] video_cache_data [0:7];
    wire [2:0] video_cache_index = video_address_sampled[2:0];
    wire video_cache_hit = video_cache_valid[video_cache_index] &&
        video_cache_address[video_cache_index] ==
            video_address_sampled[15:0];
    wire [15:0] video_lookahead_candidate =
        video_address_sampled[15:0] + 16'd3;
    wire [2:0] video_lookahead_index = video_lookahead_candidate[2:0];
    wire video_lookahead_hit = video_cache_valid[video_lookahead_index] &&
        video_cache_address[video_lookahead_index] ==
            video_lookahead_candidate;
    reg [19:0] video_lookahead_pending_address;
    reg video_lookahead_pending;
    reg request_video_demand;

    // READ commands remain burst-length one, but up to four commands are
    // issued on consecutive controller clocks. At CAS latency two the data
    // then returns on consecutive clocks. Addresses travel beside the valid
    // pipeline so each word is placed in the correct cache entry.
    reg [2:0] video_read_target_count;
    reg [2:0] video_read_issue_count;
    reg [2:0] video_read_capture_count;
    reg [2:0] video_read_valid_pipeline;
    reg [15:0] video_read_address_pipeline [0:2];
    reg [3:0] video_cache_epoch;
    reg [3:0] request_cache_epoch;

    reg [16:0] cpu_observed_address;
    reg cpu_observed_valid;
    reg [16:0] cpu_pending_address;
    reg cpu_read_pending;
    reg cpu_write_enable_previous;

    // A 6809 interrupt pushes several bytes in consecutive bus cycles.  A
    // single pending-write register can silently discard one of those bytes
    // while video owns SDRAM, eventually corrupting an RTI return address.
    // Keep every observed write until the SDRAM command engine accepts it.
    localparam integer WRITE_FIFO_DEPTH = (1 << WRITE_FIFO_LOG2);
    reg [16:0] cpu_write_fifo_address [0:WRITE_FIFO_DEPTH-1];
    reg [7:0]  cpu_write_fifo_data [0:WRITE_FIFO_DEPTH-1];
    reg [WRITE_FIFO_LOG2-1:0] cpu_write_fifo_write_pointer;
    reg [WRITE_FIFO_LOG2-1:0] cpu_write_fifo_read_pointer;
    reg [WRITE_FIFO_LOG2:0] cpu_write_fifo_count;
    reg [7:0] cpu_write_fifo_high_water;
    reg [7:0] cpu_write_drop_count;

    // The CoCo CPU bus is generated at 25.2 MHz while this controller runs at
    // 126 MHz, so its controls use two-stage capture. The GIME video address
    // changes on the falling 25.2 MHz edge and is sampled directly here on a
    // related 126 MHz rising edge, preserving the fixed video-fetch budget.
    (* ASYNC_REG = "TRUE" *) reg [16:0] cpu_address_meta;
    (* ASYNC_REG = "TRUE" *) reg [16:0] cpu_address_sync;
    (* ASYNC_REG = "TRUE" *) reg [7:0] cpu_write_data_meta;
    (* ASYNC_REG = "TRUE" *) reg [7:0] cpu_write_data_sync;
    (* ASYNC_REG = "TRUE" *) reg cpu_read_enable_meta;
    (* ASYNC_REG = "TRUE" *) reg cpu_read_enable_sync;
    (* ASYNC_REG = "TRUE" *) reg cpu_write_enable_meta;
    (* ASYNC_REG = "TRUE" *) reg cpu_write_enable_sync;

    wire [16:0] cpu_write_fifo_head_address =
        cpu_write_fifo_address[cpu_write_fifo_read_pointer];
    wire [7:0] cpu_write_fifo_head_data =
        cpu_write_fifo_data[cpu_write_fifo_read_pointer];
    wire cpu_write_fifo_empty = cpu_write_fifo_count == 0;
    wire cpu_write_fifo_full = cpu_write_fifo_count == WRITE_FIFO_DEPTH;
    // Normal refreshes are accumulated during active display and issued in
    // horizontal blanking.  This prevents PRECHARGE/REFRESH/ACTIVATE from
    // crossing the GIME's fixed ten-memory-clock word-fetch deadline.  The
    // saturated-debt fallback protects SDRAM retention if video_blank is
    // ever missing or stuck low.
    wire refresh_emergency = refresh_debt == 4'hf;
    wire cpu_write_video_collision = !cpu_write_fifo_empty && video_pending &&
        cpu_write_fifo_head_address[16:1] == video_pending_address[15:0];
    wire refresh_priority = refresh_debt != 0 || refresh_emergency;
    wire cpu_write_fifo_pop = state == STATE_IDLE && !refresh_priority &&
        !cpu_write_fifo_empty &&
        (!video_pending || cpu_write_video_collision);
    wire cpu_write_event = ready && cpu_write_enable_sync &&
        !cpu_write_enable_previous;
    wire cpu_write_fifo_push = cpu_write_event &&
        (!cpu_write_fifo_full || cpu_write_fifo_pop);
    wire refresh_due = ready && refresh_count == REFRESH_CLOCKS - 1;
    wire refresh_service = ready && state == STATE_REFRESH;

    // DD WW VV MC: dropped writes, FIFO high-water mark, missed video-word
    // deadlines, maximum refresh debt (M), and current refresh debt (C).
    // This is sampled by the UART
    // monitor. A missed deadline means the GIME advanced its RAM address
    // before the requested word reached video_read_data.
    assign debug_status = {cpu_write_drop_count,
                           cpu_write_fifo_high_water,
                           video_deadline_miss_count,
                           refresh_debt_max[3:0], refresh_debt};
    integer bank_index;
    integer cache_index;

    // Commands are active low.  Every state starts from a deselected NOP and
    // overrides these signals only when issuing a command.
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
            clear_word <= 0;
            request_word <= 0;
            request_write_data <= 0;
            request_dqm <= 2'b11;
            request_write <= 1'b0;
            request_owner <= OWNER_CLEAR;
            request_cpu_lane <= 1'b0;
            open_valid <= 4'b0000;
            for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1)
                open_row[bank_index] <= 0;

            video_observed_address <= 0;
            video_observed_valid <= 1'b0;
            video_address_sampled <= 0;
            video_blank_sampled <= 1'b1;
            video_pending_address <= 0;
            video_pending <= 1'b0;
            video_input_address_previous <= 0;
            video_input_address_valid <= 1'b0;
            video_result_address <= 0;
            video_result_valid <= 1'b0;
            video_deadline_miss_count <= 0;
            video_cache_valid <= 0;
            for (cache_index = 0; cache_index < 8;
                 cache_index = cache_index + 1) begin
                video_cache_address[cache_index] <= 0;
                video_cache_data[cache_index] <= 0;
            end
            video_lookahead_pending_address <= 0;
            video_lookahead_pending <= 1'b0;
            request_video_demand <= 1'b0;
            video_read_target_count <= 0;
            video_read_issue_count <= 0;
            video_read_capture_count <= 0;
            video_read_valid_pipeline <= 0;
            for (cache_index = 0; cache_index < 3;
                 cache_index = cache_index + 1)
                video_read_address_pipeline[cache_index] <= 0;
            video_cache_epoch <= 0;
            request_cache_epoch <= 0;
            cpu_observed_address <= 0;
            cpu_observed_valid <= 1'b0;
            cpu_pending_address <= 0;
            cpu_read_pending <= 1'b0;
            cpu_write_enable_previous <= 1'b0;
            cpu_write_fifo_write_pointer <= 0;
            cpu_write_fifo_read_pointer <= 0;
            cpu_write_fifo_count <= 0;
            cpu_write_fifo_high_water <= 0;
            cpu_write_drop_count <= 0;
            cpu_address_meta <= 0;
            cpu_address_sync <= 0;
            cpu_write_data_meta <= 0;
            cpu_write_data_sync <= 0;
            cpu_read_enable_meta <= 1'b0;
            cpu_read_enable_sync <= 1'b0;
            cpu_write_enable_meta <= 1'b0;
            cpu_write_enable_sync <= 1'b0;
            cpu_read_data <= 0;
            video_sdram_read_data <= 0;
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
            cpu_address_meta <= cpu_address;
            cpu_address_sync <= cpu_address_meta;
            cpu_write_data_meta <= cpu_write_data;
            cpu_write_data_sync <= cpu_write_data_meta;
            cpu_read_enable_meta <= cpu_read_enable;
            cpu_read_enable_sync <= cpu_read_enable_meta;
            cpu_write_enable_meta <= cpu_write_enable;
            cpu_write_enable_sync <= cpu_write_enable_meta;
            cpu_write_enable_previous <= cpu_write_enable_sync;
            // Retain the sampled signals for diagnostics while the temporary
            // BRAM shadow removes video traffic from SDRAM arbitration.
            video_address_sampled <= video_address;
            video_blank_sampled <= video_blank;

            // Read and video requests each use a one-entry queue. CPU writes
            // use the FIFO below so consecutive bus writes cannot be lost
            // while SDRAM is servicing video or refresh traffic.
            if (ready) begin
                if (cpu_read_enable_sync &&
                    (!cpu_observed_valid ||
                     cpu_address_sync != cpu_observed_address) &&
                    !cpu_read_pending) begin
                    cpu_pending_address <= cpu_address_sync;
                    cpu_observed_address <= cpu_address_sync;
                    cpu_observed_valid <= 1'b1;
                    cpu_read_pending <= 1'b1;
                end
                if (cpu_write_fifo_push) begin
                    cpu_write_fifo_address[cpu_write_fifo_write_pointer] <=
                        cpu_address_sync;
                    cpu_write_fifo_data[cpu_write_fifo_write_pointer] <=
                        cpu_write_data_sync;
                    cpu_write_fifo_write_pointer <=
                        cpu_write_fifo_write_pointer + 1'b1;
                    if (cpu_observed_valid &&
                        cpu_observed_address == cpu_address_sync)
                        cpu_observed_valid <= 1'b0;
                end
                if (cpu_write_event && !cpu_write_fifo_push &&
                    cpu_write_drop_count != 8'hff)
                    cpu_write_drop_count <= cpu_write_drop_count + 1'b1;

                // Invalidate immediately when a CPU write is observed, not
                // when SDRAM eventually accepts it. The epoch also prevents
                // an already-running video read from repopulating stale data
                // after this invalidation.
                if (cpu_write_event) begin
                    video_cache_valid <= 0;
                    video_cache_epoch <= video_cache_epoch + 1'b1;
                    video_lookahead_pending <= 1'b0;
                    if (cpu_address_sync[0])
                        video_shadow_high[cpu_address_sync[16:1]] <=
                            cpu_write_data_sync;
                    else
                        video_shadow_low[cpu_address_sync[16:1]] <=
                            cpu_write_data_sync;
                end

                if (refresh_due) begin
                    refresh_count <= 0;
                end else begin
                    refresh_count <= refresh_count + 1'b1;
                end
            end

            if (cpu_write_fifo_pop)
                cpu_write_fifo_read_pointer <=
                    cpu_write_fifo_read_pointer + 1'b1;
            case ({cpu_write_fifo_push, cpu_write_fifo_pop})
                2'b10: begin
                    cpu_write_fifo_count <= cpu_write_fifo_count + 1'b1;
                    if (cpu_write_fifo_count + 1'b1 >
                        cpu_write_fifo_high_water)
                        cpu_write_fifo_high_water <=
                            cpu_write_fifo_count + 1'b1;
                end
                2'b01:
                    cpu_write_fifo_count <= cpu_write_fifo_count - 1'b1;
                default: begin end
            endcase

            // Count every refresh that becomes due.  Servicing one refresh
            // removes exactly one debt; simultaneous due/service leaves the
            // debt unchanged.  Saturation makes a controller failure visible
            // without allowing the counter to wrap back to zero.
            case ({refresh_due, refresh_service})
                2'b10: if (refresh_debt != 4'hf)
                    refresh_debt <= refresh_debt + 1'b1;
                2'b01: if (refresh_debt != 0)
                    refresh_debt <= refresh_debt - 1'b1;
                default: begin end
            endcase
            if (refresh_due && !refresh_service &&
                refresh_debt != 4'hf &&
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
                    // PRECHARGE ALL; A10 selects all banks.
                    sdram_ras_n <= 1'b0;
                    sdram_we_n <= 1'b0;
                    sdram_address[10] <= 1'b1;
                    open_valid <= 4'b0000;
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
                    // Burst length 1, sequential, CAS latency 2. A9 also
                    // selects single-location writes.
                    sdram_ras_n <= 1'b0;
                    sdram_cas_n <= 1'b0;
                    sdram_we_n <= 1'b0;
                    sdram_address <= 13'h220;
                    wait_count <= 8'd1;
                    wait_return_state <= STATE_CLEAR_SELECT;
                    state <= STATE_WAIT;
                end

                STATE_WAIT: begin
                    if (wait_count == 0)
                        state <= wait_return_state;
                    else
                        wait_count <= wait_count - 1'b1;
                end

                STATE_CLEAR_SELECT: begin
                    request_word <= clear_word;
                    request_write_data <= 16'h0000;
                    request_dqm <= 2'b00;
                    request_write <= 1'b1;
                    request_owner <= OWNER_CLEAR;
                    state <= STATE_PREPARE;
                end

                STATE_IDLE: begin
                    // The GIME consumes each word on a fixed schedule and
                    // cannot stall, unlike the CPU request detector. Always
                    // start a waiting video word first, except when a queued
                    // CPU write targets that exact word and must become
                    // visible before it is fetched. Refresh debt is normally
                    // repaid only while video is blank so a refresh cannot
                    // steal an active-display fetch slot.
                    if (refresh_priority) begin
                        state <= STATE_REFRESH_PRE;
                    end else if (cpu_write_video_collision) begin
                        request_word <= {8'b00000000,
                                         cpu_write_fifo_head_address[16:1]};
                        request_write_data <= {cpu_write_fifo_head_data,
                                               cpu_write_fifo_head_data};
                        request_dqm <= cpu_write_fifo_head_address[0]
                            ? 2'b01 : 2'b10;
                        request_write <= 1'b1;
                        request_owner <= OWNER_CPU_WRITE;
                        request_cpu_lane <= cpu_write_fifo_head_address[0];
                        state <= STATE_PREPARE;
                    end else if (video_pending) begin
                        // Match the present 128 KiB BRAM's address aliasing:
                        // only the low 16 word-address bits are implemented.
                        request_word <= {8'b00000000,
                                         video_pending_address[15:0]};
                        request_write_data <= 0;
                        request_dqm <= 2'b00;
                        request_write <= 1'b0;
                        request_owner <= OWNER_VIDEO;
                        request_video_demand <= 1'b1;
                        request_cache_epoch <= video_cache_epoch;
                        video_pending <= 1'b0;
                        state <= STATE_PREPARE;
                    end else if (!cpu_write_fifo_empty) begin
                        request_word <= {8'b00000000,
                                         cpu_write_fifo_head_address[16:1]};
                        request_write_data <= {cpu_write_fifo_head_data,
                                               cpu_write_fifo_head_data};
                        request_dqm <= cpu_write_fifo_head_address[0]
                            ? 2'b01 : 2'b10;
                        request_write <= 1'b1;
                        request_owner <= OWNER_CPU_WRITE;
                        request_cpu_lane <= cpu_write_fifo_head_address[0];
                        state <= STATE_PREPARE;
                    end else if (video_lookahead_pending) begin
                        request_word <= {8'b00000000,
                            video_lookahead_pending_address[15:0]};
                        request_write_data <= 0;
                        request_dqm <= 2'b00;
                        request_write <= 1'b0;
                        request_owner <= OWNER_VIDEO;
                        request_video_demand <= 1'b0;
                        request_cache_epoch <= video_cache_epoch;
                        video_lookahead_pending <= 1'b0;
                        state <= STATE_PREPARE;
                    end else if (cpu_read_pending) begin
                        request_word <= {8'b00000000,
                                         cpu_pending_address[16:1]};
                        request_write_data <= 0;
                        request_dqm <= 2'b00;
                        request_write <= 1'b0;
                        request_owner <= OWNER_CPU_READ;
                        request_cpu_lane <= cpu_pending_address[0];
                        cpu_read_pending <= 1'b0;
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
                    // Three 126 MHz command-clock periods are 23.8 ns and
                    // satisfy tRP for the -6 SDRAM.
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
                    // Match the conservative 23.8 ns row-activation delay.
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
                        wait_count <= 8'd0;
                        wait_return_state <= STATE_COMPLETE;
                        state <= STATE_WAIT;
                    end else begin
                        // CAS latency two: capture on the controller edge
                        // immediately following the second SDRAM clock edge.
                        if (request_owner == OWNER_VIDEO) begin
                            // Never pipeline across a 512-word row boundary;
                            // the next miss will perform the required
                            // PRECHARGE/ACTIVATE sequence normally.
                            if (request_column >= 9'd509)
                                video_read_target_count <=
                                    10'd512 - request_column;
                            else
                                video_read_target_count <= 3'd4;
                            video_read_issue_count <= 3'd1;
                            video_read_capture_count <= 0;
                            video_read_valid_pipeline <= 3'b001;
                            video_read_address_pipeline[0] <=
                                request_word[15:0];
                            video_read_address_pipeline[1] <= 0;
                            video_read_address_pipeline[2] <= 0;
                            state <= STATE_VIDEO_STREAM;
                        end else begin
                            wait_count <= 8'd1;
                            wait_return_state <= STATE_CAPTURE;
                            state <= STATE_WAIT;
                        end
                    end
                end

                STATE_VIDEO_STREAM: begin
                    // Advance the command-to-data correspondence pipeline.
                    video_read_valid_pipeline <=
                        {video_read_valid_pipeline[1:0], 1'b0};
                    video_read_address_pipeline[2] <=
                        video_read_address_pipeline[1];
                    video_read_address_pipeline[1] <=
                        video_read_address_pipeline[0];

                    // With the row already open, consecutive BL1 READ
                    // commands may be issued on consecutive SDRAM clocks.
                    if (video_read_issue_count < video_read_target_count) begin
                        sdram_bank <= request_bank;
                        sdram_address[8:0] <= request_column +
                            video_read_issue_count;
                        sdram_address[10] <= 1'b0;
                        sdram_cas_n <= 1'b0;
                        video_read_valid_pipeline[0] <= 1'b1;
                        video_read_address_pipeline[0] <=
                            request_word[15:0] + video_read_issue_count;
                        video_read_issue_count <=
                            video_read_issue_count + 1'b1;
                    end

                    if (video_read_valid_pipeline[2]) begin
                        if (request_cache_epoch == video_cache_epoch &&
                            !cpu_write_event) begin
                            video_cache_valid[
                                video_read_address_pipeline[2][2:0]] <= 1'b1;
                            video_cache_address[
                                video_read_address_pipeline[2][2:0]] <=
                                    video_read_address_pipeline[2];
                            video_cache_data[
                                video_read_address_pipeline[2][2:0]] <= data_in;
                        end
                        if (request_video_demand &&
                            video_read_capture_count == 0) begin
                            video_sdram_read_data <= data_in;
                            video_result_address <= request_word[15:0];
                            video_result_valid <= 1'b1;
                        end
                        video_read_capture_count <=
                            video_read_capture_count + 1'b1;
                        if (video_read_capture_count + 1'b1 ==
                            video_read_target_count)
                            state <= STATE_COMPLETE;
                    end
                end

                STATE_CAPTURE: begin
                    if (request_owner == OWNER_VIDEO) begin
                        video_sdram_read_data <= data_in;
                        video_result_address <= request_word[15:0];
                        video_result_valid <= 1'b1;
                        state <= STATE_COMPLETE;
                    end
                    else if (request_owner == OWNER_CPU_READ) begin
                        cpu_read_data <= request_cpu_lane
                            ? data_in[15:8] : data_in[7:0];
                        state <= STATE_COMPLETE;
                    end else begin
                        state <= STATE_COMPLETE;
                    end
                end

                STATE_COMPLETE: begin
                    if (request_owner == OWNER_CLEAR) begin
                        if (clear_word == CLEAR_WORDS - 1) begin
                            ready <= 1'b1;
                            refresh_count <= 0;
                            state <= STATE_IDLE;
                        end else begin
                            clear_word <= clear_word + 1'b1;
                            state <= STATE_CLEAR_SELECT;
                        end
                    end else begin
                        state <= STATE_IDLE;
                    end
                end

                STATE_REFRESH_PRE: begin
                    sdram_ras_n <= 1'b0;
                    sdram_we_n <= 1'b0;
                    sdram_address[10] <= 1'b1;
                    open_valid <= 4'b0000;
                    wait_count <= 8'd1;
                    wait_return_state <= STATE_REFRESH;
                    state <= STATE_WAIT;
                end

                STATE_REFRESH: begin
                    sdram_ras_n <= 1'b0;
                    sdram_cas_n <= 1'b0;
                    // A proactive refresh restarts the interval even when no
                    // debt had accumulated yet.
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
