`timescale 1ns/1ps
`default_nettype none

// Standalone firmware runner.  It loads the generated bare-metal RV32IM image
// into the untouched UltraEmbedded TCM wrapper, then connects its AXI-Lite
// port to project-owned UART and SD SPI MMIO.
module ultraembedded_manager_sd_fat32 (
    input wire clock, input wire reset, output wire uart_tx,
    output wire sd_cs_n, output wire sd_sck, output wire sd_mosi, input wire sd_miso
);
    wire t_awvalid, t_awready, t_wvalid, t_wready, t_wlast, t_bvalid, t_bready;
    wire [31:0] t_awaddr, t_wdata, t_araddr, t_rdata;
    wire [3:0] t_awid, t_wstrb, t_bid, t_arid, t_rid;
    wire [7:0] t_awlen, t_arlen;
    wire [1:0] t_awburst, t_bresp, t_arburst, t_rresp;
    wire t_arvalid, t_arready, t_rvalid, t_rready, t_rlast;
    wire i_awvalid, i_awready, i_wvalid, i_wready, i_bvalid, i_bready;
    wire [31:0] i_awaddr, i_wdata, i_araddr, i_rdata;
    wire [3:0] i_wstrb;
    wire [1:0] i_bresp, i_rresp;
    wire i_arvalid, i_arready, i_rvalid, i_rready;
    wire boot_done;

    manager_firmware_loader loader_i (
        .clock(clock), .reset(reset), .done(boot_done),
        .axi_awvalid(t_awvalid), .axi_awready(t_awready), .axi_awaddr(t_awaddr),
        .axi_awid(t_awid), .axi_awlen(t_awlen), .axi_awburst(t_awburst),
        .axi_wvalid(t_wvalid), .axi_wready(t_wready), .axi_wdata(t_wdata),
        .axi_wstrb(t_wstrb), .axi_wlast(t_wlast), .axi_bvalid(t_bvalid),
        .axi_bready(t_bready), .axi_bresp(t_bresp), .axi_bid(t_bid),
        .axi_arvalid(t_arvalid), .axi_arready(t_arready), .axi_araddr(t_araddr),
        .axi_arid(t_arid), .axi_arlen(t_arlen), .axi_arburst(t_arburst),
        .axi_rvalid(t_rvalid), .axi_rready(t_rready), .axi_rdata(t_rdata),
        .axi_rresp(t_rresp), .axi_rid(t_rid), .axi_rlast(t_rlast)
    );
    riscv_tcm_top #(.BOOT_VECTOR(32'h00002000)) cpu_i (
        .clk_i(clock), .rst_i(reset), .rst_cpu_i(reset | !boot_done),
        .axi_i_awready_i(i_awready), .axi_i_wready_i(i_wready),
        .axi_i_bvalid_i(i_bvalid), .axi_i_bresp_i(i_bresp),
        .axi_i_arready_i(i_arready), .axi_i_rvalid_i(i_rvalid),
        .axi_i_rdata_i(i_rdata), .axi_i_rresp_i(i_rresp),
        .axi_t_awvalid_i(t_awvalid), .axi_t_awaddr_i(t_awaddr), .axi_t_awid_i(t_awid),
        .axi_t_awlen_i(t_awlen), .axi_t_awburst_i(t_awburst),
        .axi_t_wvalid_i(t_wvalid), .axi_t_wdata_i(t_wdata), .axi_t_wstrb_i(t_wstrb),
        .axi_t_wlast_i(t_wlast), .axi_t_bready_i(t_bready), .axi_t_arvalid_i(t_arvalid),
        .axi_t_araddr_i(t_araddr), .axi_t_arid_i(t_arid), .axi_t_arlen_i(t_arlen),
        .axi_t_arburst_i(t_arburst), .axi_t_rready_i(t_rready), .intr_i(32'b0),
        .axi_i_awvalid_o(i_awvalid), .axi_i_awaddr_o(i_awaddr), .axi_i_wvalid_o(i_wvalid),
        .axi_i_wdata_o(i_wdata), .axi_i_wstrb_o(i_wstrb), .axi_i_bready_o(i_bready),
        .axi_i_arvalid_o(i_arvalid), .axi_i_araddr_o(i_araddr), .axi_i_rready_o(i_rready),
        .axi_t_awready_o(t_awready), .axi_t_wready_o(t_wready), .axi_t_bvalid_o(t_bvalid),
        .axi_t_bresp_o(t_bresp), .axi_t_bid_o(t_bid), .axi_t_arready_o(t_arready),
        .axi_t_rvalid_o(t_rvalid), .axi_t_rdata_o(t_rdata), .axi_t_rresp_o(t_rresp),
        .axi_t_rid_o(t_rid), .axi_t_rlast_o(t_rlast)
    );
    manager_sd_mmio mmio_i (
        .clock(clock), .reset(reset), .axi_awvalid(i_awvalid), .axi_awready(i_awready),
        .axi_awaddr(i_awaddr), .axi_wvalid(i_wvalid), .axi_wready(i_wready),
        .axi_wdata(i_wdata), .axi_wstrb(i_wstrb), .axi_bvalid(i_bvalid), .axi_bready(i_bready),
        .axi_bresp(i_bresp), .axi_arvalid(i_arvalid), .axi_arready(i_arready),
        .axi_araddr(i_araddr), .axi_rvalid(i_rvalid), .axi_rready(i_rready),
        .axi_rdata(i_rdata), .axi_rresp(i_rresp), .uart_tx(uart_tx),
        .sd_cs_n(sd_cs_n), .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(sd_miso)
    );
endmodule

module manager_firmware_loader (
    input wire clock, input wire reset, output reg done,
    output wire axi_awvalid, input wire axi_awready, output wire [31:0] axi_awaddr,
    output wire [3:0] axi_awid, output wire [7:0] axi_awlen, output wire [1:0] axi_awburst,
    output wire axi_wvalid, input wire axi_wready, output wire [31:0] axi_wdata,
    output wire [3:0] axi_wstrb, output wire axi_wlast, input wire axi_bvalid,
    output wire axi_bready, input wire [1:0] axi_bresp, input wire [3:0] axi_bid,
    output wire axi_arvalid, input wire axi_arready, output wire [31:0] axi_araddr,
    output wire [3:0] axi_arid, output wire [7:0] axi_arlen, output wire [1:0] axi_arburst,
    input wire axi_rvalid, output wire axi_rready, input wire [31:0] axi_rdata,
    input wire [1:0] axi_rresp, input wire [3:0] axi_rid, input wire axi_rlast
);
    localparam ST_WRITE = 2'd0, ST_RESPONSE = 2'd1, ST_DONE = 2'd2;
    reg [1:0] state;
    reg [15:0] word_index;
    reg aw_sent, w_sent;
`include "rv32_sd_list_program.vh"
    assign axi_awvalid = state == ST_WRITE && !aw_sent;
    assign axi_awaddr = 32'h00002000 + {14'b0, word_index, 2'b00};
    assign axi_awid = 0; assign axi_awlen = 0; assign axi_awburst = 2'b01;
    assign axi_wvalid = state == ST_WRITE && !w_sent;
    assign axi_wdata = manager_program_word(word_index);
    assign axi_wstrb = 4'b1111; assign axi_wlast = 1'b1; assign axi_bready = 1'b1;
    assign axi_arvalid = 1'b0; assign axi_araddr = 0; assign axi_arid = 0;
    assign axi_arlen = 0; assign axi_arburst = 2'b01; assign axi_rready = 1'b1;
    wire _unused = &{axi_bresp,axi_bid,axi_arready,axi_rvalid,axi_rdata,axi_rresp,axi_rid,axi_rlast};
    always @(posedge clock) begin
        if (reset) begin state <= ST_WRITE; word_index <= 0; aw_sent <= 0; w_sent <= 0; done <= 0; end
        else case (state)
            ST_WRITE: begin
                if (axi_awvalid && axi_awready) aw_sent <= 1'b1;
                if (axi_wvalid && axi_wready) w_sent <= 1'b1;
                if ((aw_sent || (axi_awvalid && axi_awready)) && (w_sent || (axi_wvalid && axi_wready)))
                    state <= ST_RESPONSE;
            end
            ST_RESPONSE: if (axi_bvalid) begin
                aw_sent <= 0; w_sent <= 0;
                if (word_index + 1'b1 == MANAGER_PROGRAM_WORDS) begin done <= 1'b1; state <= ST_DONE; end
                else begin word_index <= word_index + 1'b1; state <= ST_WRITE; end
            end
            default: begin end
        endcase
    end
endmodule

`default_nettype wire
