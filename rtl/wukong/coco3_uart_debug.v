`default_nettype none

// Low-rate, passive CPU trace for the onboard USB-to-UART bridge. Events that
// occur while a line is being sent are intentionally coalesced; the once-per-
// second PC snapshot remains useful even when the CPU is in a tight loop.
module coco3_uart_debug (
    input  wire         clock,
    input  wire         reset,
    input  wire [15:0]  cpu_address,
    input  wire [15:0]  cpu_pc,
    input  wire         cpu_vma,
    input  wire         cpu_read,
    input  wire [7:0]   cpu_read_data,
    input  wire [7:0]   cpu_write_data,
    input  wire         keyboard_active,
    input  wire         cartridge_enabled,
    input  wire [7:0]   sd_status,
    // Mode, resolution, bank, base(16), horizontal offset, palettes(96), RAM word.
    input  wire [159:0] video_state,
    // INIT0, INIT1, MMU-enable/task/all-RAM flags, then task-0/task-1 maps.
    input  wire [7:0]   gime_init0,
    input  wire [7:0]   gime_init1,
    input  wire [2:0]   memory_flags,
    input  wire [127:0] mmu_state,
    // DD WW RR CC: dropped writes, write-FIFO high-water mark, maximum
    // refresh debt, and current refresh debt.
    input  wire [31:0]  sdram_debug_status,
    output wire         uart_tx_o
);
    localparam [2:0] MSG_READY = 3'd0;
    localparam [2:0] MSG_CART  = 3'd1;
    localparam [2:0] MSG_ENTRY = 3'd2;
    localparam [2:0] MSG_PC    = 3'd3;

    reg [24:0] second_count;
    reg boot_pending;
    reg cart_previous;
    reg cart_entry_seen;
    reg message_active;
    reg [2:0] message_kind;
    reg [7:0] message_index;
    reg [159:0] captured_video;
    reg [7:0] captured_gime_init0;
    reg [7:0] captured_gime_init1;
    reg [2:0] captured_memory_flags;
    reg [127:0] captured_mmu;
    reg [31:0] captured_sdram_debug_status;
    reg [15:0] captured_pc;
    reg captured_cart;
    reg captured_key;
    reg [7:0] captured_row;
    reg [7:0] captured_column;
    reg [7:0] captured_sd_status;
    reg [15:0] sampled_cpu_pc;
    reg [7:0] last_keyboard_row;
    reg [7:0] last_keyboard_column;
    reg [7:0] tx_data;
    reg tx_start;
    wire tx_busy;

    function [7:0] hex_digit;
        input [3:0] value;
        begin
            hex_digit = value < 10 ? (8'h30 + value) : (8'h41 + value - 10);
        end
    endfunction

    function [7:0] message_length;
        input [2:0] kind;
        begin
            case (kind)
                MSG_READY: message_length = 18;
                MSG_CART:  message_length = 9;
                MSG_ENTRY: message_length = 17;
                default:   message_length = 130;
            endcase
        end
    endfunction

    function [7:0] message_byte;
        input [2:0] kind;
        input [7:0] index;
        input [15:0] pc;
        input cart;
        input key;
        input [7:0] row;
        input [7:0] column;
        input [7:0] sd_status_value;
        input [159:0] video;
        input [7:0] init0;
        input [7:0] init1;
        input [2:0] flags;
        input [127:0] mmu;
        input [31:0] sdram_debug;
        begin
            message_byte = 8'h20;
            case (kind)
                MSG_READY: case (index)
                    0:message_byte="C"; 1:message_byte="O";
                    2:message_byte="C"; 3:message_byte="O";
                    4:message_byte="3"; 5:message_byte=" ";
                    6:message_byte="U"; 7:message_byte="A";
                    8:message_byte="R"; 9:message_byte="T";
                    10:message_byte=" "; 11:message_byte="R";
                    12:message_byte="E"; 13:message_byte="A";
                    14:message_byte="D"; 15:message_byte="Y";
                    16:message_byte=8'h0d; default:message_byte=8'h0a;
                endcase
                MSG_CART: case (index)
                    0:message_byte="C"; 1:message_byte="A";
                    2:message_byte="R"; 3:message_byte="T";
                    4:message_byte=" "; 5:message_byte="O";
                    6:message_byte="N";
                    7:message_byte=8'h0d; default:message_byte=8'h0a;
                endcase
                MSG_ENTRY: case (index)
                    0:message_byte="C"; 1:message_byte="A";
                    2:message_byte="R"; 3:message_byte="T";
                    4:message_byte=" "; 5:message_byte="E";
                    6:message_byte="N"; 7:message_byte="T";
                    8:message_byte="R"; 9:message_byte="Y";
                    10:message_byte=" "; 11:message_byte="C";
                    12:message_byte="0"; 13:message_byte="0";
                    14:message_byte="0";
                    15:message_byte=8'h0d; default:message_byte=8'h0a;
                endcase
                default: case (index)
                    0:message_byte="P"; 1:message_byte="C";
                    2:message_byte="=";
                    3:message_byte=hex_digit(pc[15:12]);
                    4:message_byte=hex_digit(pc[11:8]);
                    5:message_byte=hex_digit(pc[7:4]);
                    6:message_byte=hex_digit(pc[3:0]);
                    7:message_byte=" "; 8:message_byte="K";
                    9:message_byte="=";
                    10:message_byte=(key ? "1" : "0");
                    11:message_byte=" "; 12:message_byte="R";
                    13:message_byte="=";
                    14:message_byte=hex_digit(row[7:4]);
                    15:message_byte=hex_digit(row[3:0]);
                    16:message_byte=" "; 17:message_byte="C";
                    18:message_byte="=";
                    19:message_byte=hex_digit(column[7:4]);
                    20:message_byte=hex_digit(column[3:0]);
                    21:message_byte=" "; 22:message_byte="S";
                    23:message_byte="=";
                    24:message_byte=hex_digit(sd_status_value[7:4]);
                    25:message_byte=hex_digit(sd_status_value[3:0]);
                    26:message_byte=" "; 27:message_byte="T";
                    28:message_byte="=";
                    29:message_byte="0";
                    30:message_byte=(cart ? "1" : "0");
                    31:message_byte=" "; 32:message_byte="V";
                    33:message_byte="=";
                    74:message_byte=" "; 75:message_byte="G";
                    76:message_byte="=";
                    77:message_byte=hex_digit(init0[7:4]);
                    78:message_byte=hex_digit(init0[3:0]);
                    79:message_byte=hex_digit(init1[7:4]);
                    80:message_byte=hex_digit(init1[3:0]);
                    81:message_byte=hex_digit({1'b0,flags});
                    82:message_byte=" "; 83:message_byte="M";
                    84:message_byte="=";
                    117:message_byte=" ";
                    118:message_byte="D";
                    119:message_byte="=";
                    128:message_byte=8'h0d;
                    129:message_byte=8'h0a;
                    default: begin
                        if (index >= 34 && index <= 73)
                            message_byte=hex_digit(video[159-(index-34)*4 -: 4]);
                        else if (index >= 85 && index <= 116)
                            message_byte=hex_digit(mmu[127-(index-85)*4 -: 4]);
                        else if (index >= 120 && index <= 127)
                            message_byte=hex_digit(
                                sdram_debug[31-(index-120)*4 -: 4]);
                    end
                endcase
            endcase
        end
    endfunction

    uart_tx #(.CLKS_PER_BIT(219)) transmitter_i (
        .clock(clock), .reset(reset), .data(tx_data), .start(tx_start),
        .tx(uart_tx_o), .busy(tx_busy)
    );

    always @(posedge clock) begin
        if (reset) begin
            second_count <= 25'd0;
            boot_pending <= 1'b1;
            cart_previous <= 1'b0;
            cart_entry_seen <= 1'b0;
            message_active <= 1'b0;
            message_kind <= MSG_READY;
            message_index <= 7'd0;
            captured_pc <= 16'd0;
            captured_video <= 160'd0;
            captured_gime_init0 <= 8'd0;
            captured_gime_init1 <= 8'd0;
            captured_memory_flags <= 3'd0;
            captured_mmu <= 128'd0;
            captured_sdram_debug_status <= 32'd0;
            captured_cart <= 1'b0;
            captured_key <= 1'b0;
            captured_row <= 8'hff;
            captured_column <= 8'hff;
            captured_sd_status <= 8'hff;
            sampled_cpu_pc <= 16'h0000;
            last_keyboard_row <= 8'hff;
            last_keyboard_column <= 8'hff;
            tx_data <= 8'd0;
            tx_start <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            cart_previous <= cartridge_enabled;
            // cpu_pc is the MC6809 architectural PC snapshot, not an opcode
            // trace. Sampling it continuously gives each status line a stable
            // value without touching the CPU bus or adding wait states.
            sampled_cpu_pc <= cpu_pc;
            if (cpu_vma && !cpu_read && cpu_address == 16'hff02)
                last_keyboard_column <= cpu_write_data;
            if (cpu_vma && cpu_read && cpu_address == 16'hff00)
                last_keyboard_row <= cpu_read_data;
            if (second_count == 25'd25199999)
                second_count <= 25'd0;
            else
                second_count <= second_count + 1'b1;

            if (!message_active) begin
                if (boot_pending) begin
                    boot_pending <= 1'b0;
                    message_kind <= MSG_READY;
                    message_index <= 7'd0;
                    message_active <= 1'b1;
                end else if (cartridge_enabled && !cart_previous) begin
                    cart_entry_seen <= 1'b0;
                    message_kind <= MSG_CART;
                    message_index <= 7'd0;
                    message_active <= 1'b1;
                end else if (cartridge_enabled && !cart_entry_seen &&
                             cpu_vma && cpu_read &&
                             cpu_address == 16'hc000) begin
                    cart_entry_seen <= 1'b1;
                    message_kind <= MSG_ENTRY;
                    message_index <= 7'd0;
                    message_active <= 1'b1;
                end else if (second_count == 25'd25199999) begin
                    captured_pc <= sampled_cpu_pc;
                    captured_video <= video_state;
                    captured_gime_init0 <= gime_init0;
                    captured_gime_init1 <= gime_init1;
                    captured_memory_flags <= memory_flags;
                    captured_mmu <= mmu_state;
                    captured_sdram_debug_status <= sdram_debug_status;
                    captured_cart <= cartridge_enabled;
                    captured_key <= keyboard_active;
                    captured_row <= last_keyboard_row;
                    captured_column <= last_keyboard_column;
                    captured_sd_status <= sd_status;
                    message_kind <= MSG_PC;
                    message_index <= 7'd0;
                    message_active <= 1'b1;
                end
            end else if (!tx_busy && !tx_start) begin
                tx_data <= message_byte(message_kind, message_index,
                                        captured_pc, captured_cart, captured_key,
                                        captured_row, captured_column,
                                        captured_sd_status, captured_video,
                                        captured_gime_init0,
                                        captured_gime_init1,
                                        captured_memory_flags, captured_mmu,
                                        captured_sdram_debug_status);
                tx_start <= 1'b1;
                if (message_index + 1'b1 == message_length(message_kind)) begin
                    message_active <= 1'b0;
                    message_index <= 7'd0;
                end else begin
                    message_index <= message_index + 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
