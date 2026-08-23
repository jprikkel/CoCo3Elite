`timescale 1ns/1ps
`default_nettype none

module coco3_boot_system (
    input wire pixel_clk, input wire reset,
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
    integer i;

    coco3_boot_machine machine_i (
        .clock(pixel_clk), .reset(reset), .debug_address(cpu_address),
        .debug_vma(), .debug_read(), .debug_ram_write(),
        .debug_io_write(io_write), .debug_write_data(cpu_data),
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
            red={color[5:4],color[5:4],color[5:4],color[5:4]};
            green={color[3:2],color[3:2],color[3:2],color[3:2]};
            blue={color[1:0],color[1:0],color[1:0],color[1:0]};
        end else begin
            red={palette[color[3:0]][5:4],palette[color[3:0]][5:4],palette[color[3:0]][5:4],palette[color[3:0]][5:4]};
            green={palette[color[3:0]][3:2],palette[color[3:0]][3:2],palette[color[3:0]][3:2],palette[color[3:0]][3:2]};
            blue={palette[color[3:0]][1:0],palette[color[3:0]][1:0],palette[color[3:0]][1:0],palette[color[3:0]][1:0]};
        end
    end
    wire _unused = sync_flag;
endmodule
`default_nettype wire
