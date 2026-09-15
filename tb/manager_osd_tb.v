`timescale 1ns/1ps
module manager_osd_tb;
    reg clock=0,reset=1,active=1;
    reg [9:0] x=0,y=0;
    reg [4:0] selected_row=0;
    reg narrow_selection=0;
    reg option_selection=0;
    reg [1:0] font_style=0;
    wire [10:0] char_address;
    reg [7:0] char_data=8'h41;
    wire [7:0] red,green,blue;
    always #5 clock=~clock;

    manager_osd dut(.clock(clock),.reset(reset),.active(active),
        .screen_x(x),.screen_y(y),.selected_row(selected_row),
        .narrow_selection(narrow_selection),
        .option_selection(option_selection),
        .font_style(font_style),
        .char_address(char_address),.char_data(char_data),
        .red(red),.green(green),.blue(blue));

    initial begin
        #12 reset=0;
        x=32;y=16;#1;
        if(char_address!==0) $fatal(1,"top-left address is %0d",char_address);
        if(dut.font_address!==13'h0410) $fatal(1,"ASCII A font address is %04h",dut.font_address);
        if(dut.font_i.memory[65*16+2]!==8'h7c)
            $fatal(1,"management font is not Spleen 8x16");
        if(dut.font_i.memory[2048+65*16+3]!==8'h18 ||
           dut.font_i.memory[4096+65*16+2]!==8'h3c)
            $fatal(1,"selectable bitmap typefaces are missing");
        x=607;y=463;#1;
        if(char_address!==2015) $fatal(1,"bottom-right address is %0d",char_address);
        if(!dut.inside) $fatal(1,"bottom-right pixel is outside");
        x=608;#1;
        if(dut.inside) $fatal(1,"right edge extends past centered 576-pixel window");
        x=31;#1;
        if(dut.inside) $fatal(1,"left edge starts before x=32");
        // A selected row uses solid amber reverse video only in the file pane.
        selected_row=7;char_data=8'h20;x=32+5*8;y=16+7*16;
        @(posedge clock);#1;
        if({red,green,blue}!==24'hffd070)
            $fatal(1,"selected file background is %02h%02h%02h",red,green,blue);
        char_data=8'h41;x=32+5*8+1;y=16+7*16+2;
        @(posedge clock);#1;
        if({red,green,blue}!==24'h000000)
            $fatal(1,"selected file text is not black: %02h%02h%02h",red,green,blue);
        x=32+60*8;
        @(posedge clock);#1;
        if({red,green,blue}!==24'h020200)
            $fatal(1,"details pane was incorrectly highlighted: %02h%02h%02h",red,green,blue);
        // Setup mode confines reverse video to its narrower category pane.
        narrow_selection=1;char_data=8'h20;x=32+24*8;
        @(posedge clock);#1;
        if({red,green,blue}!==24'hffd070)
            $fatal(1,"setup category highlight ended too early");
        x=32+25*8;
        @(posedge clock);#1;
        if({red,green,blue}!==24'h020200)
            $fatal(1,"setup category highlight crossed its divider");
        narrow_selection=0;
        // Option focus highlights only the setup value pane.
        option_selection=1;selected_row=6;char_data=8'h20;x=32+27*8;y=16+6*16;
        @(posedge clock);#1;
        if({red,green,blue}!==24'hffd070)
            $fatal(1,"setup option highlight did not start at value pane");
        x=32+26*8;
        @(posedge clock);#1;
        if({red,green,blue}!==24'h020200)
            $fatal(1,"setup option highlight crossed into label pane");
        option_selection=0;
        // Custom icon 80 is an up arrow. Row 3, bit 4 must be amber.
        selected_row=31;char_data=8'h80;x=32+3;y=16+3;
        @(posedge clock);#1;
        if({red,green,blue}!==24'hffd070)
            $fatal(1,"parent icon pixel is %02h%02h%02h",red,green,blue);
        // Dedicated line glyphs are three pixels thick.
        char_data=8'h90;x=32;y=16+7;
        @(posedge clock);#1;
        if({red,green,blue}!==24'hffd070)
            $fatal(1,"solid horizontal rule pixel is %02h%02h%02h",red,green,blue);
        y=16+9;
        @(posedge clock);#1;
        if({red,green,blue}!==24'hffd070)
            $fatal(1,"third horizontal rule pixel is %02h%02h%02h",red,green,blue);
        // Every curved step is exactly three pixels wide. Only the three-row
        // junction combines the vertical and horizontal strokes.
        if(dut.custom_row(7'h12,4'd3)!==8'h07 ||
           dut.custom_row(7'h12,4'd4)!==8'h0e ||
           dut.custom_row(7'h12,4'd5)!==8'h1c ||
           dut.custom_row(7'h12,4'd6)!==8'h38 ||
           dut.custom_row(7'h12,4'd7)!==8'h3f ||
           dut.custom_row(7'h12,4'd10)!==8'h38)
            $fatal(1,"top-left corner thickness or junction is incorrect");
        if(dut.custom_row(7'h13,4'd3)!==8'he0 ||
           dut.custom_row(7'h13,4'd4)!==8'h70 ||
           dut.custom_row(7'h13,4'd5)!==8'h38 ||
           dut.custom_row(7'h13,4'd6)!==8'h1c ||
           dut.custom_row(7'h13,4'd7)!==8'hfc ||
           dut.custom_row(7'h13,4'd10)!==8'h1c)
            $fatal(1,"top-right corner thickness or junction is incorrect");
        if(dut.custom_row(7'h14,4'd6)!==8'h38 ||
           dut.custom_row(7'h14,4'd7)!==8'h3f ||
           dut.custom_row(7'h14,4'd10)!==8'h38 ||
           dut.custom_row(7'h14,4'd11)!==8'h1c ||
           dut.custom_row(7'h14,4'd12)!==8'h0e ||
           dut.custom_row(7'h14,4'd13)!==8'h07)
            $fatal(1,"bottom-left corner thickness or junction is incorrect");
        if(dut.custom_row(7'h15,4'd6)!==8'h1c ||
           dut.custom_row(7'h15,4'd7)!==8'hfc ||
           dut.custom_row(7'h15,4'd10)!==8'h1c ||
           dut.custom_row(7'h15,4'd11)!==8'h38 ||
           dut.custom_row(7'h15,4'd12)!==8'h70 ||
           dut.custom_row(7'h15,4'd13)!==8'he0)
            $fatal(1,"bottom-right corner thickness or junction is incorrect");
        // The rounded corner starts inward before joining the frame.
        char_data=8'h92;x=32+2;y=16+3;
        @(posedge clock);#1;
        if({red,green,blue}!==24'h020200)
            $fatal(1,"rounded corner outer pixel is not clear");
        x=32+5;
        @(posedge clock);#1;
        if({red,green,blue}!==24'hffd070)
            $fatal(1,"rounded corner arc pixel is missing");
        // The left separator cap starts at pixel two of the next cell.  With
        // the outer frame ending at pixel four, this leaves exactly five
        // clear pixels before the separator begins.
        char_data=8'h9c;x=32+8;y=16+7;
        @(posedge clock);#1;
        if({red,green,blue}!==24'h020200)
            $fatal(1,"separator cap did not preserve outer gap");
        x=32+10;
        @(posedge clock);#1;
        if({red,green,blue}!==24'hffd070)
            $fatal(1,"separator cap start pixel is missing");
        // Logo slash glyphs share a three-pixel diagonal shape but each has
        // its own foreground color.
        selected_row=31;x=32+5;y=16+2;
        char_data=8'h9e;@(posedge clock);#1;
        if({red,green,blue}!==24'hff2820)
            $fatal(1,"red logo slash is %02h%02h%02h",red,green,blue);
        char_data=8'h9f;@(posedge clock);#1;
        if({red,green,blue}!==24'h20e848)
            $fatal(1,"green logo slash is %02h%02h%02h",red,green,blue);
        char_data=8'ha0;@(posedge clock);#1;
        if({red,green,blue}!==24'h3070ff)
            $fatal(1,"blue logo slash is %02h%02h%02h",red,green,blue);
        if(dut.custom_row(7'h21,4'd7)!==8'h70 ||
           dut.custom_row(7'h22,4'd7)!==8'h0e)
            $fatal(1,"setup value arrows are incorrect");
        $display("PASS: aligned frame, RGB logo, font styles, arrows, and selection");
        $finish;
    end
endmodule
