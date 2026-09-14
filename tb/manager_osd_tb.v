`timescale 1ns/1ps
module manager_osd_tb;
    reg clock=0,reset=1,active=1;
    reg [9:0] x=0,y=0;
    reg [4:0] selected_row=0;
    wire [10:0] char_address;
    reg [7:0] char_data=8'h41;
    wire [7:0] red,green,blue;
    always #5 clock=~clock;

    manager_osd dut(.clock(clock),.reset(reset),.active(active),
        .screen_x(x),.screen_y(y),.selected_row(selected_row),
        .char_address(char_address),.char_data(char_data),
        .red(red),.green(green),.blue(blue));

    initial begin
        #12 reset=0;
        x=32;y=16;#1;
        if(char_address!==0) $fatal(1,"top-left address is %0d",char_address);
        if(dut.font_address!==11'h410) $fatal(1,"ASCII A font address is %03h",dut.font_address);
        if(dut.font_i.memory[65*16+2]!==8'h7c)
            $fatal(1,"management font is not Spleen 8x16");
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
        // The rounded corner starts inward before joining the frame.
        char_data=8'h92;x=32+2;y=16+3;
        @(posedge clock);#1;
        if({red,green,blue}!==24'h020200)
            $fatal(1,"rounded corner outer pixel is not clear");
        x=32+4;
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
        $display("PASS: sentence-case OSD with RGB logo and amber reverse-video selection");
        $finish;
    end
endmodule
