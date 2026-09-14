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
        x=607;y=463;#1;
        if(char_address!==2015) $fatal(1,"bottom-right address is %0d",char_address);
        if(!dut.inside) $fatal(1,"bottom-right pixel is outside");
        x=608;#1;
        if(dut.inside) $fatal(1,"right edge extends past centered 576-pixel window");
        x=31;#1;
        if(dut.inside) $fatal(1,"left edge starts before x=32");
        // A selected row highlights only the file pane, matching the browser
        // mockup while preserving the dark details pane on the right.
        selected_row=7;char_data=8'h20;x=32+5*8;y=16+7*16;
        @(posedge clock);#1;
        if({red,green,blue}!==24'h00a8b8)
            $fatal(1,"selected file background is %02h%02h%02h",red,green,blue);
        x=32+60*8;
        @(posedge clock);#1;
        if({red,green,blue}!==24'h020200)
            $fatal(1,"details pane was incorrectly highlighted: %02h%02h%02h",red,green,blue);
        // Custom icon 80 is an up arrow. Row 3, bit 4 must be amber.
        selected_row=31;char_data=8'h80;x=32+3;y=16+3;
        @(posedge clock);#1;
        if({red,green,blue}!==24'hffd070)
            $fatal(1,"parent icon pixel is %02h%02h%02h",red,green,blue);
        // Dedicated line glyphs fill adjacent cell edges and are not dashed.
        char_data=8'h90;x=32;y=16+7;
        @(posedge clock);#1;
        if({red,green,blue}!==24'hffd070)
            $fatal(1,"solid horizontal rule pixel is %02h%02h%02h",red,green,blue);
        $display("PASS: wide light-amber/teal OSD, split selection, and file icons");
        $finish;
    end
endmodule
