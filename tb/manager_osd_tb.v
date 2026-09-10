`timescale 1ns/1ps
module manager_osd_tb;
    reg clock=0,reset=1,active=1;
    reg [9:0] x=0,y=0;
    reg [4:0] selected_row=0;
    wire [9:0] char_address;
    reg [7:0] char_data=8'h41;
    wire [7:0] red,green,blue;
    always #5 clock=~clock;

    manager_osd dut(.clock(clock),.reset(reset),.active(active),
        .screen_x(x),.screen_y(y),.selected_row(selected_row),
        .char_address(char_address),.char_data(char_data),
        .red(red),.green(green),.blue(blue));

    initial begin
        #12 reset=0;
        x=128;y=80;#1;
        if(char_address!==0) $fatal(1,"top-left address is %0d",char_address);
        if(dut.font_address!==11'h410) $fatal(1,"ASCII A font address is %03h",dut.font_address);
        x=511;y=399;#1;
        if(char_address!==959) $fatal(1,"bottom-right address is %0d",char_address);
        if(!dut.inside) $fatal(1,"bottom-right pixel is outside");
        x=512;#1;
        if(dut.inside) $fatal(1,"right edge extends past centered 384-pixel window");
        x=127;#1;
        if(dut.inside) $fatal(1,"left edge starts before x=128");
        $display("PASS: centered OSD bounds and seven-bit ASCII font addressing");
        $finish;
    end
endmodule
