`timescale 1ns/1ps
module cpu_reset_tb;
    reg clk=0, rst=1;
    always #20 clk=~clk;
    reg hold=1;
    integer divider=0;
    integer speed=7;
    always @(posedge clk) begin
        if (rst) begin divider<=0; hold<=1; end
        else if (divider>=speed-1) begin divider<=0; hold<=0; end
        else begin divider<=divider+1; hold<=1; end
    end
    wire [15:0] addr;
    wire [15:0] debug_pc;
    wire [7:0] dout;
    wire vma,rw;
    reg [7:0] din;
    // Reset entry writes a signature, then loops elsewhere. A reset must
    // fetch the vector and write the signature again, not resume the loop.
    always @(posedge clk) case(addr)
        16'hfffe: din<=8'h10;
        16'hffff: din<=8'h00;
        16'h1000: din<=8'h86; // LDA #$5A
        16'h1001: din<=8'h5a;
        16'h1002: din<=8'hb7; // STA $2000
        16'h1003: din<=8'h20;
        16'h1004: din<=8'h00;
        16'h1005: din<=8'h20; // BRA $1005
        16'h1006: din<=8'hfe;
        default: din<=8'h12;
    endcase
    cpu09 dut(.clk(clk),.rst(rst),.hold(hold),.addr(addr),.rw(rw),
        .debug_pc(debug_pc),
        .data_in(din),.data_out(dout),.vma(vma),.irq(1'b0),
        .firq(1'b0),.nmi(1'b0),.halt(1'b0));
    integer writes=0, vectors=0;
    always @(posedge clk) if(!hold && vma) begin
        if(rst) $fatal(1,"Bus service during reset");
        if(rw && addr==16'hfffe) vectors=vectors+1;
        if(!rw && addr==16'h2000 && dout==8'h5a) writes=writes+1;
    end
    integer mode,p,old_writes,old_vectors;
    initial begin
        repeat(100) @(posedge clk);
        #1 rst=0;
        repeat(2000) @(posedge clk);
        if(writes==0) $fatal(1,"Initial boot failed");
        for(mode=0;mode<2;mode=mode+1) begin
            speed=mode ? 4 : 7;
            for(p=0;p<4;p=p+1) begin
                wait(dut.phase==p && addr==16'h1005);
                @(posedge clk); #1;
                old_writes=writes; old_vectors=vectors; rst=1;
                repeat(100+p) @(posedge clk);
                #1 rst=0;
                repeat(2000) @(posedge clk);
                if(writes<=old_writes || vectors<=old_vectors)
                    $fatal(1,"Reset missed: speed=%0d phase=%0d writes=%0d vectors=%0d",speed,p,writes,vectors);
                if(debug_pc!==16'h1005 && debug_pc!==16'h1006 && debug_pc!==16'h1007)
                    $fatal(1,"PC snapshot does not show the running loop: %h",debug_pc);
            end
        end
        $display("PASS: running CPU restarts through reset vector in all four phases at both speeds");
        $finish;
    end
    initial begin #10000000; $fatal(1,"Reset test timed out"); end
endmodule
