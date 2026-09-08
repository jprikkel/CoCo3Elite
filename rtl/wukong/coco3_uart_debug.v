`default_nettype none

// Low-rate, passive CPU trace for the onboard USB-to-UART bridge. Events that
// occur while a line is being sent are intentionally coalesced; the once-per-
// second PC snapshot remains useful even when the CPU is in a tight loop.
module coco3_uart_debug (
    input  wire        clock,
    input  wire        reset,
    input  wire [15:0] cpu_address,
    input  wire [15:0] cpu_pc,
    input  wire        cpu_vma,
    input  wire        cpu_read,
    input  wire        cpu_opfetch,
    input  wire [7:0]  cpu_read_data,
    input  wire [7:0]  cpu_write_data,
    input  wire        keyboard_active,
    input  wire        cartridge_enabled,
    // Mode, resolution, bank, base(16), horizontal offset, palettes(96), RAM word.
    input  wire [159:0] video_state,
    output wire        uart_tx_o
);
    localparam [1:0] MSG_READY = 2'd0;
    localparam [1:0] MSG_CART  = 2'd1;
    localparam [1:0] MSG_ENTRY = 2'd2;
    localparam [1:0] MSG_PC    = 2'd3;

    reg [24:0] second_count;
    reg boot_pending;
    reg cart_previous;
    reg cart_entry_seen;
    reg message_active;
    reg [1:0] message_kind;
    reg [6:0] message_index;
    reg [159:0] captured_video;
    reg [15:0] captured_pc;
    reg captured_cart;
    reg captured_key;
    reg [7:0] captured_row;
    reg [7:0] captured_column;
    reg [15:0] last_opcode_pc;
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

    function [6:0] message_length;
        input [1:0] kind;
        begin
            case (kind)
                MSG_READY: message_length = 18;
                MSG_CART:  message_length = 9;
                MSG_ENTRY: message_length = 17;
                default:   message_length = 66;
            endcase
        end
    endfunction

    function [7:0] message_byte;
        input [1:0] kind;
        input [6:0] index;
        input [15:0] pc;
        input cart;
        input key;
        input [7:0] row;
        input [7:0] column;
        input [159:0] video;
        begin
            message_byte = 8'h20;
            case (kind)
                MSG_READY: case (index)
                    0:message_byte=8'h43; 1:message_byte=8'h4f;
                    2:message_byte=8'h43; 3:message_byte=8'h4f;
                    4:message_byte=8'h33; 5:message_byte=8'h20;
                    6:message_byte=8'h55; 7:message_byte=8'h41;
                    8:message_byte=8'h52; 9:message_byte=8'h54;
                    10:message_byte=8'h20; 11:message_byte=8'h52;
                    12:message_byte=8'h45; 13:message_byte=8'h41;
                    14:message_byte=8'h44; 15:message_byte=8'h59;
                    16:message_byte=8'h0d; default:message_byte=8'h0a;
                endcase
                MSG_CART: case (index)
                    0:message_byte=8'h43; 1:message_byte=8'h41;
                    2:message_byte=8'h52; 3:message_byte=8'h54;
                    4:message_byte=8'h20; 5:message_byte=8'h4f;
                    6:message_byte=8'h4e;
                    7:message_byte=8'h0d; default:message_byte=8'h0a;
                endcase
                MSG_ENTRY: case (index)
                    0:message_byte=8'h43; 1:message_byte=8'h41;
                    2:message_byte=8'h52; 3:message_byte=8'h54;
                    4:message_byte=8'h20; 5:message_byte=8'h45;
                    6:message_byte=8'h4e; 7:message_byte=8'h54;
                    8:message_byte=8'h52; 9:message_byte=8'h59;
                    10:message_byte=8'h20; 11:message_byte=8'h43;
                    12:message_byte=8'h30; 13:message_byte=8'h30;
                    14:message_byte=8'h30;
                    15:message_byte=8'h0d; default:message_byte=8'h0a;
                endcase
                default: case (index)
                    0:message_byte=8'h50; 1:message_byte=8'h43;
                    2:message_byte=8'h3d;
                    3:message_byte=hex_digit(pc[15:12]);
                    4:message_byte=hex_digit(pc[11:8]);
                    5:message_byte=hex_digit(pc[7:4]);
                    6:message_byte=hex_digit(pc[3:0]);
                    7:message_byte=8'h20; 8:message_byte=8'h4b;
                    9:message_byte=8'h3d;
                    10:message_byte=(key ? 8'h31 : 8'h30);
                    11:message_byte=8'h20; 12:message_byte=8'h52;
                    13:message_byte=8'h3d;
                    14:message_byte=hex_digit(row[7:4]);
                    15:message_byte=hex_digit(row[3:0]);
                    16:message_byte=8'h20; 17:message_byte=8'h43;
                    18:message_byte=8'h3d;
                    19:message_byte=hex_digit(column[7:4]);
                    20:message_byte=hex_digit(column[3:0]);
                    21:message_byte=8'h20;
                    22:message_byte=8'h56;
                    23:message_byte=8'h3d;
                    64:message_byte=8'h0d;
                    65:message_byte=8'h0a;
                    default:message_byte=hex_digit(video[159-(index-24)*4 -: 4]);
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
            message_index <= 5'd0;
            captured_pc <= 16'd0;
            captured_video <= 160'd0;
            captured_cart <= 1'b0;
            captured_key <= 1'b0;
            captured_row <= 8'hff;
            captured_column <= 8'hff;
            last_opcode_pc <= 16'h0000;
            last_keyboard_row <= 8'hff;
            last_keyboard_column <= 8'hff;
            tx_data <= 8'd0;
            tx_start <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            cart_previous <= cartridge_enabled;
            // MC6809 exposes its architectural PC through the unmodified
            // RegData port. This is a register snapshot, not an opcode trace.
            last_opcode_pc <= cpu_pc;
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
                    message_index <= 5'd0;
                    message_active <= 1'b1;
                end else if (cartridge_enabled && !cart_previous) begin
                    cart_entry_seen <= 1'b0;
                    message_kind <= MSG_CART;
                    message_index <= 5'd0;
                    message_active <= 1'b1;
                end else if (cartridge_enabled && !cart_entry_seen && cpu_vma &&
                             cpu_read && cpu_address == 16'hc000) begin
                    cart_entry_seen <= 1'b1;
                    message_kind <= MSG_ENTRY;
                    message_index <= 5'd0;
                    message_active <= 1'b1;
                end else if (second_count == 25'd25199999) begin
                    captured_pc <= last_opcode_pc;
                    captured_video <= video_state;
                    captured_cart <= cartridge_enabled;
                    captured_key <= keyboard_active;
                    captured_row <= last_keyboard_row;
                    captured_column <= last_keyboard_column;
                    message_kind <= MSG_PC;
                    message_index <= 5'd0;
                    message_active <= 1'b1;
                end
            end else if (!tx_busy && !tx_start) begin
                tx_data <= message_byte(message_kind, message_index,
                                        captured_pc, captured_cart, captured_key,
                                        captured_row, captured_column, captured_video);
                tx_start <= 1'b1;
                if (message_index + 1'b1 == message_length(message_kind)) begin
                    message_active <= 1'b0;
                    message_index <= 5'd0;
                end else begin
                    message_index <= message_index + 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
