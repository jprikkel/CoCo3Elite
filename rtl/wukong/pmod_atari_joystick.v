`timescale 1ns/1ps
`default_nettype none

// Synchronize six active-low contacts from a passive Atari/C64-style
// joystick adapter. Pull-ups live at the FPGA pins; each switch closes to
// ground. Mechanical switch bounce is acceptable to the CoCo PIA interface,
// so this block adds only the two-clock metastability guard.
module pmod_atari_joystick (
    input  wire clock,
    input  wire reset,
    input  wire up_n,
    input  wire down_n,
    input  wire left_n,
    input  wire right_n,
    input  wire button1_n,
    input  wire button2_n,
    output wire up,
    output wire down,
    output wire left,
    output wire right,
    output wire button1,
    output wire button2
);
    (* ASYNC_REG = "TRUE" *) reg [5:0] contact_meta;
    (* ASYNC_REG = "TRUE" *) reg [5:0] contact_sync;

    always @(posedge clock) begin
        if (reset) begin
            contact_meta <= 6'b111111;
            contact_sync <= 6'b111111;
        end else begin
            contact_meta <= {button2_n, button1_n, right_n,
                             left_n, down_n, up_n};
            contact_sync <= contact_meta;
        end
    end

    assign up      = !contact_sync[0];
    assign down    = !contact_sync[1];
    assign left    = !contact_sync[2];
    assign right   = !contact_sync[3];
    assign button1 = !contact_sync[4];
    assign button2 = !contact_sync[5];
endmodule

`default_nettype wire
