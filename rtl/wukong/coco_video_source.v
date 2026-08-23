`default_nettype none

module coco_video_source (
    input  wire       pixel_clk,
    input  wire       reset,
    output wire       hsync,
    output wire       vsync,
    output wire       video_enable,
    output reg  [7:0] red,
    output reg  [7:0] green,
    output reg  [7:0] blue
);
    wire [8:0] color;
    wire hblank;
    wire vblank;
    wire sync_flag;
    wire [19:0] video_address;
    wire [15:0] video_data;

    coco3_synthetic_video_ram video_ram_i (
        .address(video_address),
        .data   (video_data)
    );

    COCO3VIDEO video_i (
        .PIX_CLK        (pixel_clk),
        .RESET_N        (~reset),
        .COLOR          (color),
        .HSYNC          (hsync),
        .SYNC_FLAG      (sync_flag),
        .VSYNC          (vsync),
        .HBLANKING      (hblank),
        .VBLANKING      (vblank),
        .RAM_ADDRESS    (video_address),
        .RAM_DATA       (video_data),
        .COCO           (1'b0),
        .V              (3'b000),
        .BP             (1'b0),
        .VERT           (7'h00),
        .VID_CONT       (4'h0),
        .CSS            (1'b0),
        .LPF            (2'b00),
        .VERT_FIN_SCRL  (4'h0),
        .HLPR           (1'b0),
        .LPR            (3'b101),
        .HRES           (4'b0101),
        .CRES           (2'b00),
        .HVEN           (1'b0),
        .HOR_OFFSET     (7'h00),
        .SCRN_START_HSB (2'b00),
        .SCRN_START_MSB (8'h00),
        .SCRN_START_LSB (8'h00),
        .BLINK          (1'b1),
        .SWITCH5        (1'b0)
    );

    assign video_enable = ~(hblank | vblank);

    // Diagnostic palette. It makes both indexed legacy colors and the special
    // direct-color encoding visible without depending on live GIME registers.
    always @* begin
        if (color[8]) begin
            red   = {color[5:4], color[5:4], color[5:4], color[5:4]};
            green = {color[3:2], color[3:2], color[3:2], color[3:2]};
            blue  = {color[1:0], color[1:0], color[1:0], color[1:0]};
        end else begin
            case (color[3:0])
                4'h0: {red, green, blue} = 24'h000000;
                4'h1: {red, green, blue} = 24'h0000AA;
                4'h2: {red, green, blue} = 24'h00AA00;
                4'h3: {red, green, blue} = 24'h00AAAA;
                4'h4: {red, green, blue} = 24'hAA0000;
                4'h5: {red, green, blue} = 24'hAA00AA;
                4'h6: {red, green, blue} = 24'hAA5500;
                4'h7: {red, green, blue} = 24'hAAAAAA;
                4'h8: {red, green, blue} = 24'h101830;
                4'h9: {red, green, blue} = 24'h3030FF;
                4'hA: {red, green, blue} = 24'h30FF30;
                4'hB: {red, green, blue} = 24'h30FFFF;
                4'hC: {red, green, blue} = 24'h40FF70;
                4'hD: {red, green, blue} = 24'h081008;
                4'hE: {red, green, blue} = 24'hFFFF40;
                4'hF: {red, green, blue} = 24'hFFFFFF;
            endcase
        end
    end

    wire _unused = sync_flag;
endmodule

`default_nettype wire
