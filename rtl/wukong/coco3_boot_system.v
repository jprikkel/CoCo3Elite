`timescale 1ns/1ps
`default_nettype none

module coco3_boot_system (
    input wire pixel_clk, input wire reset,
    input wire ps2_clk, input wire ps2_data,
    output wire hsync, output wire vsync, output wire video_enable,
    output reg [7:0] red, output reg [7:0] green, output reg [7:0] blue
);
    wire [15:0] cpu_address;
    wire io_write;
    wire [7:0] cpu_data;
    wire [19:0] video_address;
    wire [15:0] video_data;
    wire [8:0] color;
    wire hblank, vblank, sync_flag;
    reg coco;
    reg [2:0] v;
    reg bp;
    reg [6:0] vert;
    reg [3:0] vid_cont;
    reg css;
    reg [2:0] lpr;
    reg hlpr;
    reg [1:0] lpf, cres;
    reg [3:0] hres, scroll;
    reg hven;
    reg [6:0] hor_offset;
    reg [1:0] start_hsb;
    reg [7:0] start_msb, start_lsb;
    reg [5:0] palette [0:15];
    reg pia_ddr4;
    reg [3:0] direct_red, direct_green, direct_blue;
    integer i;
    wire [55:0] keyboard_keys;
    wire keyboard_shift;
    wire keyboard_shift_override;
    wire keyboard_reset;

    COCOKEY keyboard_i (
        .RESET_N(~reset),
        .CLK50MHZ(pixel_clk),
        .SLO_CLK(pixel_clk),
        .PS2_CLK(ps2_clk),
        .PS2_DATA(ps2_data),
        .KEY(keyboard_keys),
        .SHIFT(keyboard_shift),
        .SHIFT_OVERRIDE(keyboard_shift_override),
        .RESET(keyboard_reset)
    );

    coco3_boot_machine machine_i (
        .clock(pixel_clk), .reset(reset), .debug_address(cpu_address),
        .debug_vma(), .debug_read(), .debug_ram_write(),
        .debug_io_write(io_write), .debug_write_data(cpu_data),
        .keyboard_keys(keyboard_keys),
        .keyboard_shift(keyboard_shift),
        .keyboard_shift_override(keyboard_shift_override),
        .video_hsync(hsync), .video_vsync(vsync),
        .video_address(video_address), .video_read_data(video_data)
    );

    always @(posedge pixel_clk) begin
        if (reset) begin
            coco <= 0; v <= 0; bp <= 0; vert <= 0; vid_cont <= 0; css <= 0;
            lpr <= 0; hlpr <= 0; lpf <= 0; cres <= 0; hres <= 0;
            scroll <= 0; hven <= 0; hor_offset <= 0;
            start_hsb <= 0; start_msb <= 0; start_lsb <= 0;
            pia_ddr4 <= 0;
            for (i=0; i<16; i=i+1) palette[i] <= i;
        end else if (io_write) begin
            case (cpu_address)
                16'hFF90: coco <= cpu_data[7];
                16'hFF98: begin bp <= cpu_data[7]; hres[3] <= cpu_data[6]; lpr <= cpu_data[2:0]; end
                16'hFF99: begin hlpr <= cpu_data[7]; lpf <= cpu_data[6:5]; hres[2:0] <= cpu_data[4:2]; cres <= cpu_data[1:0]; end
                16'hFF9B: start_hsb <= cpu_data[1:0];
                16'hFF9C: scroll <= cpu_data[3:0];
                16'hFF9D: start_msb <= cpu_data;
                16'hFF9E: start_lsb <= cpu_data;
                16'hFF9F: begin hven <= cpu_data[7]; hor_offset <= cpu_data[6:0]; end
                16'hFF22: if (pia_ddr4) begin
                    vid_cont <= cpu_data[7:4];
                    css <= cpu_data[3];
                end
                16'hFF23: pia_ddr4 <= cpu_data[2];
                16'hFFC0: v[0] <= 1'b0;
                16'hFFC1: v[0] <= 1'b1;
                16'hFFC2: v[1] <= 1'b0;
                16'hFFC3: v[1] <= 1'b1;
                16'hFFC4: v[2] <= 1'b0;
                16'hFFC5: v[2] <= 1'b1;
                16'hFFC6: vert[0] <= 1'b0;
                16'hFFC7: vert[0] <= 1'b1;
                16'hFFC8: vert[1] <= 1'b0;
                16'hFFC9: vert[1] <= 1'b1;
                16'hFFCA: vert[2] <= 1'b0;
                16'hFFCB: vert[2] <= 1'b1;
                16'hFFCC: vert[3] <= 1'b0;
                16'hFFCD: vert[3] <= 1'b1;
                16'hFFCE: vert[4] <= 1'b0;
                16'hFFCF: vert[4] <= 1'b1;
                16'hFFD0: vert[5] <= 1'b0;
                16'hFFD1: vert[5] <= 1'b1;
                16'hFFD2: vert[6] <= 1'b0;
                16'hFFD3: vert[6] <= 1'b1;
                default: if (cpu_address >= 16'hFFB0 && cpu_address <= 16'hFFBF)
                    palette[cpu_address[3:0]] <= cpu_data[5:0];
            endcase
        end
    end

    COCO3VIDEO video_i (
        .PIX_CLK(pixel_clk), .RESET_N(~reset), .COLOR(color), .HSYNC(hsync),
        .SYNC_FLAG(sync_flag), .VSYNC(vsync), .HBLANKING(hblank),
        .VBLANKING(vblank), .RAM_ADDRESS(video_address), .RAM_DATA(video_data),
        .VIDEO_ACTIVE(video_enable),
        .COCO(coco), .V(v), .BP(bp), .VERT(vert), .VID_CONT(vid_cont), .CSS(css),
        .LPF(lpf), .VERT_FIN_SCRL(scroll), .HLPR(hlpr), .LPR(lpr), .HRES(hres),
        .CRES(cres), .HVEN(hven), .HOR_OFFSET(hor_offset),
        .SCRN_START_HSB(start_hsb), .SCRN_START_MSB(start_msb),
        .SCRN_START_LSB(start_lsb), .BLINK(1'b1), .SWITCH5(1'b0)
    );
    always @* begin
        if (color[8]) begin
            // Preserve the four direct-color intensity modes used by the
            // original CoCo3FPGA DAC. COLOR[5:0] is R-G-B interleaved.
            case (color[7:6])
                2'b00: begin
                    direct_red   = {1'b0, color[5], color[2], 1'b0};
                    direct_green = {1'b0, color[4], color[1], 1'b0};
                    direct_blue  = {1'b0, color[3], color[0], 1'b0};
                end
                2'b01: begin
                    direct_red   = {1'b0, color[5], color[2], 1'b0} + {2'b00, color[5], color[2]};
                    direct_green = {1'b0, color[4], color[1], 1'b0} + {2'b00, color[4], color[1]};
                    direct_blue  = {1'b0, color[3], color[0], 1'b0} + {2'b00, color[3], color[0]};
                end
                2'b10: begin
                    direct_red   = {color[5], color[2], 2'b00};
                    direct_green = {color[4], color[1], 2'b00};
                    direct_blue  = {color[3], color[0], 2'b00};
                end
                default: begin
                    direct_red   = {color[5], color[2], color[5], color[2]};
                    direct_green = {color[4], color[1], color[4], color[1]};
                    direct_blue  = {color[3], color[0], color[3], color[0]};
                end
            endcase
            red   = {direct_red, direct_red};
            green = {direct_green, direct_green};
            blue  = {direct_blue, direct_blue};
        end else begin
            // GIME palette encoding is R2 G2 B2 R1 G1 B1, not RR GG BB.
            red={palette[color[3:0]][5],palette[color[3:0]][2],palette[color[3:0]][5],palette[color[3:0]][2],
                 palette[color[3:0]][5],palette[color[3:0]][2],palette[color[3:0]][5],palette[color[3:0]][2]};
            green={palette[color[3:0]][4],palette[color[3:0]][1],palette[color[3:0]][4],palette[color[3:0]][1],
                   palette[color[3:0]][4],palette[color[3:0]][1],palette[color[3:0]][4],palette[color[3:0]][1]};
            blue={palette[color[3:0]][3],palette[color[3:0]][0],palette[color[3:0]][3],palette[color[3:0]][0],
                  palette[color[3:0]][3],palette[color[3:0]][0],palette[color[3:0]][3],palette[color[3:0]][0]};
        end
    end
    wire _unused = sync_flag ^ keyboard_reset;
endmodule
`default_nettype wire
