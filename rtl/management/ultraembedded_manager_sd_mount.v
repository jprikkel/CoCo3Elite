`timescale 1ns/1ps
`default_nettype none

// RV32/FAT32 service attached to the CoCo FDC mailbox.  The imported RV32
// core stays untouched; this module supplies its loader and project MMIO.
module ultraembedded_manager_sd_mount (
    input wire clock, input wire reset, output wire uart_tx,
    output wire sd_cs_n, output wire sd_sck, output wire sd_mosi, input wire sd_miso,
    input wire [1:0] fdc_drive, input wire [7:0] fdc_track, input wire [7:0] fdc_sector, input wire [7:0] fdc_last_type1, input wire [31:0] fdc_debug_word, input wire [31:0] fdc_completed_debug_word, input wire fdc_read_complete_toggle, input wire fdc_write_complete_toggle,
    input wire fdc_request_toggle, input wire [7:0] fdc_buffer_address,
    input wire fdc_write_strobe, input wire [7:0] fdc_write_data,
    input wire [4:0] menu_key_state, input wire [9:0] osd_char_address,
    output wire [7:0] osd_char_data, output wire osd_active,
    output wire [4:0] osd_selected_row,
    output wire [7:0] fdc_buffer_data, output wire fdc_done_toggle,
    output wire fdc_success, output wire fdc_write_done_toggle, output wire fdc_write_success,
    output wire [2:0] fdc_present, output wire manager_ready
);
    wire t_awvalid,t_awready,t_wvalid,t_wready,t_wlast,t_bvalid,t_bready,t_arvalid,t_arready,t_rvalid,t_rready,t_rlast;
    wire [31:0] t_awaddr,t_wdata,t_araddr,t_rdata; wire [3:0] t_awid,t_wstrb,t_bid,t_arid,t_rid; wire [7:0] t_awlen,t_arlen; wire [1:0] t_awburst,t_bresp,t_arburst,t_rresp;
    wire i_awvalid,i_awready,i_wvalid,i_wready,i_bvalid,i_bready,i_arvalid,i_arready,i_rvalid,i_rready;
    wire [31:0] i_awaddr,i_wdata,i_araddr,i_rdata; wire [3:0] i_wstrb; wire [1:0] i_bresp,i_rresp; wire boot_done;
    manager_mount_firmware_loader loader_i(.clock(clock),.reset(reset),.done(boot_done),.axi_awvalid(t_awvalid),.axi_awready(t_awready),.axi_awaddr(t_awaddr),.axi_awid(t_awid),.axi_awlen(t_awlen),.axi_awburst(t_awburst),.axi_wvalid(t_wvalid),.axi_wready(t_wready),.axi_wdata(t_wdata),.axi_wstrb(t_wstrb),.axi_wlast(t_wlast),.axi_bvalid(t_bvalid),.axi_bready(t_bready),.axi_bresp(t_bresp),.axi_bid(t_bid));
    riscv_tcm_top #(.BOOT_VECTOR(32'h00002000)) cpu_i(.clk_i(clock),.rst_i(reset),.rst_cpu_i(reset|!boot_done),.axi_i_awready_i(i_awready),.axi_i_wready_i(i_wready),.axi_i_bvalid_i(i_bvalid),.axi_i_bresp_i(i_bresp),.axi_i_arready_i(i_arready),.axi_i_rvalid_i(i_rvalid),.axi_i_rdata_i(i_rdata),.axi_i_rresp_i(i_rresp),.axi_t_awvalid_i(t_awvalid),.axi_t_awaddr_i(t_awaddr),.axi_t_awid_i(t_awid),.axi_t_awlen_i(t_awlen),.axi_t_awburst_i(t_awburst),.axi_t_wvalid_i(t_wvalid),.axi_t_wdata_i(t_wdata),.axi_t_wstrb_i(t_wstrb),.axi_t_wlast_i(t_wlast),.axi_t_bready_i(t_bready),.axi_t_arvalid_i(1'b0),.axi_t_araddr_i(32'b0),.axi_t_arid_i(4'b0),.axi_t_arlen_i(8'b0),.axi_t_arburst_i(2'b01),.axi_t_rready_i(1'b1),.intr_i(32'b0),.axi_i_awvalid_o(i_awvalid),.axi_i_awaddr_o(i_awaddr),.axi_i_wvalid_o(i_wvalid),.axi_i_wdata_o(i_wdata),.axi_i_wstrb_o(i_wstrb),.axi_i_bready_o(i_bready),.axi_i_arvalid_o(i_arvalid),.axi_i_araddr_o(i_araddr),.axi_i_rready_o(i_rready),.axi_t_awready_o(t_awready),.axi_t_wready_o(t_wready),.axi_t_bvalid_o(t_bvalid),.axi_t_bresp_o(t_bresp),.axi_t_bid_o(t_bid),.axi_t_arready_o(t_arready),.axi_t_rvalid_o(t_rvalid),.axi_t_rdata_o(t_rdata),.axi_t_rresp_o(t_rresp),.axi_t_rid_o(t_rid),.axi_t_rlast_o(t_rlast));
    manager_sd_mmio #(.UART_CLKS_PER_BIT(219)) mmio_i(.clock(clock),.reset(reset),.axi_awvalid(i_awvalid),.axi_awready(i_awready),.axi_awaddr(i_awaddr),.axi_wvalid(i_wvalid),.axi_wready(i_wready),.axi_wdata(i_wdata),.axi_wstrb(i_wstrb),.axi_bvalid(i_bvalid),.axi_bready(i_bready),.axi_bresp(i_bresp),.axi_arvalid(i_arvalid),.axi_arready(i_arready),.axi_araddr(i_araddr),.axi_rvalid(i_rvalid),.axi_rready(i_rready),.axi_rdata(i_rdata),.axi_rresp(i_rresp),.uart_tx(uart_tx),.sd_cs_n(sd_cs_n),.sd_sck(sd_sck),.sd_mosi(sd_mosi),.sd_miso(sd_miso),.fdc_drive(fdc_drive),.fdc_track(fdc_track),.fdc_sector(fdc_sector),.fdc_last_type1(fdc_last_type1),.fdc_debug_word(fdc_debug_word),.fdc_completed_debug_word(fdc_completed_debug_word),.fdc_read_complete_toggle(fdc_read_complete_toggle),.fdc_write_complete_toggle(fdc_write_complete_toggle),.fdc_request_toggle(fdc_request_toggle),.fdc_buffer_address(fdc_buffer_address),.fdc_buffer_data(fdc_buffer_data),.fdc_write_strobe(fdc_write_strobe),.fdc_write_data(fdc_write_data),.menu_key_state(menu_key_state),.osd_char_address(osd_char_address),.osd_char_data(osd_char_data),.osd_active(osd_active),.osd_selected_row(osd_selected_row),.fdc_done_toggle(fdc_done_toggle),.fdc_success(fdc_success),.fdc_write_done_toggle(fdc_write_done_toggle),.fdc_write_success(fdc_write_success),.fdc_present(fdc_present),.manager_ready(manager_ready));
endmodule

module manager_mount_firmware_loader(
    input wire clock,input wire reset,output reg done,output wire axi_awvalid,input wire axi_awready,output wire [31:0] axi_awaddr,output wire [3:0] axi_awid,output wire [7:0] axi_awlen,output wire [1:0] axi_awburst,output wire axi_wvalid,input wire axi_wready,output wire [31:0] axi_wdata,output wire [3:0] axi_wstrb,output wire axi_wlast,input wire axi_bvalid,output wire axi_bready,input wire [1:0] axi_bresp,input wire [3:0] axi_bid
);
    localparam ST_WRITE=2'd0,ST_RESPONSE=2'd1,ST_DONE=2'd2; reg[1:0] state;reg[15:0] word_index;reg aw_sent,w_sent;
`include "rv32_sd_mount_program.vh"
    assign axi_awvalid=state==ST_WRITE&&!aw_sent;assign axi_awaddr=32'h00002000+{14'b0,word_index,2'b00};assign axi_awid=0;assign axi_awlen=0;assign axi_awburst=2'b01;assign axi_wvalid=state==ST_WRITE&&!w_sent;assign axi_wdata=manager_program_word(word_index);assign axi_wstrb=4'b1111;assign axi_wlast=1'b1;assign axi_bready=1'b1;wire _unused=&{axi_bresp,axi_bid};
    always@(posedge clock)if(reset)begin state<=ST_WRITE;word_index<=0;aw_sent<=0;w_sent<=0;done<=0;end else case(state) ST_WRITE:begin if(axi_awvalid&&axi_awready)aw_sent<=1;if(axi_wvalid&&axi_wready)w_sent<=1;if((aw_sent||(axi_awvalid&&axi_awready))&&(w_sent||(axi_wvalid&&axi_wready)))state<=ST_RESPONSE;end ST_RESPONSE:if(axi_bvalid)begin aw_sent<=0;w_sent<=0;if(word_index+1'b1==MANAGER_PROGRAM_WORDS)begin done<=1;state<=ST_DONE;end else begin word_index<=word_index+1'b1;state<=ST_WRITE;end end default:;endcase
endmodule
`default_nettype wire
