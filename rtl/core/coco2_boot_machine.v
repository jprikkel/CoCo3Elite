`timescale 1ns/1ps
`default_nettype none
module coco2_boot_machine(
 input wire clock,input wire reset,input wire [19:0] video_address,
 output wire [15:0] video_read_data,output wire [15:0] debug_address,
 output wire debug_io_write,output wire [7:0] debug_write_data
);
 reg [3:0] divider; reg hold; reg all_ram;
 wire vma,rw; wire [15:0] address; wire [7:0] dout,ram_data,rom_data;
 wire io_sel=address[15:8]==8'hFF && address[7:4]!=4'hF;
 wire vector_sel=address[15:4]==12'hFFF;
 wire rom_sel=vector_sel || (!all_ram && address>=16'h8000 && address<=16'hBFFF);
 wire active=!hold&&vma;
 wire ram_write=active&&!rw&&!io_sel&&!rom_sel;
 wire io_write=active&&!rw&&io_sel;
 wire [7:0] din=io_sel?8'hFF:(rom_sel?rom_data:ram_data);
 always @(posedge clock) begin
  if(reset) begin divider<=0;hold<=1;end
  else if(divider==13) begin divider<=0;hold<=0;end
  else begin divider<=divider+1'b1;hold<=1;end
 end
 always @(posedge clock) begin
  if(reset) all_ram<=0;
  else if(io_write&&address==16'hFFDE) all_ram<=0;
  else if(io_write&&address==16'hFFDF) all_ram<=1;
 end
 cpu09 cpu_i(.clk(clock),.rst(reset),.vma(vma),.lic_out(),.ifetch(),.opfetch(),
  .ba(),.bs(),.addr(address),.rw(rw),.data_out(dout),.data_in(din),
  .irq(1'b0),.firq(1'b0),.nmi(1'b0),.halt(1'b0),.hold(hold));
 coco2_system_rom rom_i(.clock(clock),.address(address[13:0]),.data(rom_data));
 coco3_128k_ram #(.INIT_VALUE(8'h00)) ram_i(.clock(clock),
  .cpu_address({1'b0,address}),.cpu_write_data(dout),.cpu_write_enable(ram_write),
  .cpu_read_data(ram_data),.video_address(video_address),.video_read_data(video_read_data));
 assign debug_address=address; assign debug_io_write=io_write; assign debug_write_data=dout;
endmodule
`default_nettype wire
