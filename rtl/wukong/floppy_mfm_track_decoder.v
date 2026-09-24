`timescale 1ns/1ps
`default_nettype none

// Decode one indexed 250-kbit/s MFM track from the compact interval stream
// produced by pmod_floppy_read_only. Each interval unit is two 25.2 MHz clocks.
// Nominal MFM transition spacings are therefore 50, 76, and 101 units. The
// decoder reconstructs the encoded bit stream, recognizes the missing-clock
// A1 sync word (16'h4489), checks WD-style CRC-16, and caches all eighteen
// 256-byte DECB sectors from the track.
module floppy_mfm_track_decoder (
    input  wire        clock,
    input  wire        reset,
    input  wire        start,
    input  wire        sample_valid,
    output wire        sample_ready,
    input  wire [7:0]  sample_interval,
    input  wire        sample_last,
    input  wire [12:0] cache_read_address,
    output reg  [7:0]  cache_read_data,
    output reg         busy,
    output reg         done,
    output reg         success,
    output reg  [7:0]  decoded_track,
    output reg         decoded_side,
    output reg  [17:0] sector_valid,
    output reg  [7:0]  id_crc_errors,
    output reg  [7:0]  data_crc_errors
);
    localparam [1:0] ALIGN_SEARCH = 2'd0,
                     ALIGN_SYNC   = 2'd1,
                     ALIGN_BYTES  = 2'd2;
    localparam [2:0] PARSE_MARK      = 3'd0,
                     PARSE_ID_FIELDS = 3'd1,
                     PARSE_ID_CRC1   = 3'd2,
                     PARSE_ID_CRC2   = 3'd3,
                     PARSE_DATA      = 3'd4,
                     PARSE_DATA_CRC1 = 3'd5,
                     PARSE_DATA_CRC2 = 3'd6;

    reg [1:0] align_state;
    reg [2:0] parse_state;
    reg [15:0] raw_shift;
    reg [3:0] raw_bit_count;
    reg [1:0] sync_words;
    reg [7:0] data_shift;
    reg [15:0] crc;
    reg [2:0] id_field_count;
    reg [7:0] id_track, id_side, id_sector, id_size;
    reg pending_id;
    reg [7:0] pending_sector;
    reg [8:0] data_byte_count;

    reg expand_active;
    reg [2:0] expand_slots;
    reg expand_last;
    reg decoded_bit_valid;
    reg decoded_bit;
    reg finish_pending;

    // Keep the decoded 18-sector scratchpad in distributed RAM.  The physical
    // floppy path also retains a complete revolution of raw flux in BRAM, and
    // placing both stores there exceeds the Wukong device's block-RAM budget.
    // This cache is accessed only by the low-rate floppy decoder/readback path,
    // so LUT RAM provides ample timing margin without reducing capture depth.
    (* ram_style = "distributed" *) reg [7:0] sector_cache [0:4607];
    wire [7:0] completed_byte = {data_shift[6:0], decoded_bit};
    wire [15:0] shifted_raw = {raw_shift[14:0], decoded_bit};
    wire [12:0] sector_write_address =
        ({5'b0, pending_sector} - 13'd1) * 13'd256 + data_byte_count[7:0];

    assign sample_ready = busy && !expand_active && !finish_pending;

    function [15:0] crc16_byte;
        input [15:0] current;
        input [7:0] value;
        integer bit_index;
        reg [15:0] next_crc;
        begin
            next_crc = current ^ {value, 8'h00};
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                if (next_crc[15])
                    next_crc = (next_crc << 1) ^ 16'h1021;
                else
                    next_crc = next_crc << 1;
            crc16_byte = next_crc;
        end
    endfunction

    wire [15:0] sync_crc = crc16_byte(
        crc16_byte(crc16_byte(16'hffff, 8'ha1), 8'ha1), 8'ha1);

    always @(posedge clock) begin
        cache_read_data <= sector_cache[cache_read_address];
    end

    // Expand a transition interval into two, three, or four encoded MFM bit
    // slots. The final slot contains the transition (one); preceding slots are
    // zero. Thresholds lie midway between the measured 50/76/101-unit peaks.
    always @(posedge clock) begin
        if (reset || start) begin
            expand_active <= 1'b0;
            expand_slots <= 3'b0;
            expand_last <= 1'b0;
            decoded_bit_valid <= 1'b0;
            decoded_bit <= 1'b0;
            finish_pending <= 1'b0;
        end else begin
            decoded_bit_valid <= 1'b0;
            if (sample_valid && sample_ready) begin
                expand_active <= 1'b1;
                expand_slots <= sample_interval < 8'd63 ? 3'd2 :
                                sample_interval < 8'd89 ? 3'd3 : 3'd4;
                expand_last <= sample_last;
            end else if (expand_active) begin
                decoded_bit_valid <= 1'b1;
                decoded_bit <= expand_slots == 3'd1;
                if (expand_slots == 3'd1) begin
                    expand_active <= 1'b0;
                    if (expand_last)
                        finish_pending <= 1'b1;
                end else
                    expand_slots <= expand_slots - 1'b1;
            end
            if (finish_pending && !decoded_bit_valid)
                finish_pending <= 1'b0;
        end
    end

    always @(posedge clock) begin
        if (reset) begin
            busy <= 1'b0;
            done <= 1'b0;
            success <= 1'b0;
            decoded_track <= 8'b0;
            decoded_side <= 1'b0;
            sector_valid <= 18'b0;
            id_crc_errors <= 8'b0;
            data_crc_errors <= 8'b0;
            align_state <= ALIGN_SEARCH;
            parse_state <= PARSE_MARK;
            raw_shift <= 16'b0;
            raw_bit_count <= 4'b0;
            sync_words <= 2'b0;
            data_shift <= 8'b0;
            crc <= 16'hffff;
            id_field_count <= 3'b0;
            id_track <= 8'b0;
            id_side <= 8'b0;
            id_sector <= 8'b0;
            id_size <= 8'b0;
            pending_id <= 1'b0;
            pending_sector <= 8'b0;
            data_byte_count <= 9'b0;
        end else if (start) begin
            busy <= 1'b1;
            done <= 1'b0;
            success <= 1'b0;
            decoded_track <= 8'b0;
            decoded_side <= 1'b0;
            sector_valid <= 18'b0;
            id_crc_errors <= 8'b0;
            data_crc_errors <= 8'b0;
            align_state <= ALIGN_SEARCH;
            parse_state <= PARSE_MARK;
            raw_shift <= 16'b0;
            raw_bit_count <= 4'b0;
            sync_words <= 2'b0;
            data_shift <= 8'b0;
            crc <= 16'hffff;
            id_field_count <= 3'b0;
            pending_id <= 1'b0;
            pending_sector <= 8'b0;
            data_byte_count <= 9'b0;
        end else if (busy) begin
            if (decoded_bit_valid) begin
                case (align_state)
                    ALIGN_SEARCH: begin
                        raw_shift <= shifted_raw;
                        if (shifted_raw == 16'h4489) begin
                            align_state <= ALIGN_SYNC;
                            raw_bit_count <= 4'b0;
                            sync_words <= 2'd1;
                            raw_shift <= 16'b0;
                        end
                    end
                    ALIGN_SYNC: begin
                        raw_shift <= shifted_raw;
                        if (raw_bit_count == 4'd15) begin
                            raw_bit_count <= 4'b0;
                            raw_shift <= 16'b0;
                            if (shifted_raw == 16'h4489) begin
                                if (sync_words == 2'd2) begin
                                    align_state <= ALIGN_BYTES;
                                    parse_state <= PARSE_MARK;
                                    data_shift <= 8'b0;
                                    crc <= sync_crc;
                                end else
                                    sync_words <= sync_words + 1'b1;
                            end else begin
                                align_state <= ALIGN_SEARCH;
                                sync_words <= 2'b0;
                            end
                        end else
                            raw_bit_count <= raw_bit_count + 1'b1;
                    end
                    ALIGN_BYTES: begin
                        if (raw_bit_count[0])
                            data_shift <= {data_shift[6:0], decoded_bit};
                        if (raw_bit_count == 4'd15) begin
                            raw_bit_count <= 4'b0;
                            data_shift <= 8'b0;
                            case (parse_state)
                                PARSE_MARK: begin
                                    crc <= crc16_byte(crc, completed_byte);
                                    if (completed_byte == 8'hfe) begin
                                        parse_state <= PARSE_ID_FIELDS;
                                        id_field_count <= 3'b0;
                                    end else if ((completed_byte == 8'hfb ||
                                                  completed_byte == 8'hf8) &&
                                                 pending_id) begin
                                        parse_state <= PARSE_DATA;
                                        data_byte_count <= 9'b0;
                                    end else begin
                                        align_state <= ALIGN_SEARCH;
                                        sync_words <= 2'b0;
                                    end
                                end
                                PARSE_ID_FIELDS: begin
                                    crc <= crc16_byte(crc, completed_byte);
                                    case (id_field_count)
                                        3'd0: id_track <= completed_byte;
                                        3'd1: id_side <= completed_byte;
                                        3'd2: id_sector <= completed_byte;
                                        3'd3: id_size <= completed_byte;
                                    endcase
                                    if (id_field_count == 3'd3)
                                        parse_state <= PARSE_ID_CRC1;
                                    else
                                        id_field_count <= id_field_count + 1'b1;
                                end
                                PARSE_ID_CRC1: begin
                                    crc <= crc16_byte(crc, completed_byte);
                                    parse_state <= PARSE_ID_CRC2;
                                end
                                PARSE_ID_CRC2: begin
                                    if (crc16_byte(crc, completed_byte) == 0 &&
                                        id_size == 8'd1 && id_sector >= 8'd1 &&
                                        id_sector <= 8'd18) begin
                                        pending_id <= 1'b1;
                                        pending_sector <= id_sector;
                                        decoded_track <= id_track;
                                        decoded_side <= id_side[0];
                                    end else begin
                                        pending_id <= 1'b0;
                                        if (id_crc_errors != 8'hff)
                                            id_crc_errors <= id_crc_errors + 1'b1;
                                    end
                                    align_state <= ALIGN_SEARCH;
                                    sync_words <= 2'b0;
                                end
                                PARSE_DATA: begin
                                    sector_cache[sector_write_address] <=
                                        completed_byte;
                                    crc <= crc16_byte(crc, completed_byte);
                                    if (data_byte_count == 9'd255)
                                        parse_state <= PARSE_DATA_CRC1;
                                    else
                                        data_byte_count <= data_byte_count + 1'b1;
                                end
                                PARSE_DATA_CRC1: begin
                                    crc <= crc16_byte(crc, completed_byte);
                                    parse_state <= PARSE_DATA_CRC2;
                                end
                                PARSE_DATA_CRC2: begin
                                    if (crc16_byte(crc, completed_byte) == 0)
                                        sector_valid[pending_sector - 1'b1] <= 1'b1;
                                    else if (data_crc_errors != 8'hff)
                                        data_crc_errors <= data_crc_errors + 1'b1;
                                    pending_id <= 1'b0;
                                    align_state <= ALIGN_SEARCH;
                                    sync_words <= 2'b0;
                                end
                                default: begin
                                    align_state <= ALIGN_SEARCH;
                                    sync_words <= 2'b0;
                                end
                            endcase
                        end else
                            raw_bit_count <= raw_bit_count + 1'b1;
                    end
                    default: align_state <= ALIGN_SEARCH;
                endcase
            end

            // Wait one cycle after the final expanded bit is consumed so the
            // final CRC/valid-bit update is reflected in success.
            if (finish_pending && !decoded_bit_valid) begin
                busy <= 1'b0;
                done <= 1'b1;
                success <= sector_valid != 18'b0;
            end
        end
    end
endmodule

`default_nettype wire
