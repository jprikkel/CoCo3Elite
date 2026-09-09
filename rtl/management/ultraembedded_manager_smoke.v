`timescale 1ns/1ps
`default_nettype none

// First vendor-neutral management-CPU integration test. The UltraEmbedded
// core and its TCM/AXI wrapper are imported unchanged under rtl/third-party.
// This local wrapper loads four RV32IM instructions through the wrapper's
// documented TCM AXI port, releases the CPU, and checks its AXI-Lite write to
// the first future management-peripheral address. It is deliberately not part
// of the CoCo bitstream.
module ultraembedded_manager_smoke (
    input  wire        clock,
    input  wire        reset,
    output wire        boot_done,
    output wire        magic_seen,
    output wire [31:0] magic_value
);
    wire tcm_awvalid, tcm_awready;
    wire [31:0] tcm_awaddr;
    wire [3:0] tcm_awid;
    wire [7:0] tcm_awlen;
    wire [1:0] tcm_awburst;
    wire tcm_wvalid, tcm_wready;
    wire [31:0] tcm_wdata;
    wire [3:0] tcm_wstrb;
    wire tcm_wlast, tcm_bvalid, tcm_bready;
    wire [1:0] tcm_bresp;
    wire [3:0] tcm_bid;
    wire tcm_arvalid, tcm_arready;
    wire [31:0] tcm_araddr;
    wire [3:0] tcm_arid;
    wire [7:0] tcm_arlen;
    wire [1:0] tcm_arburst;
    wire tcm_rvalid, tcm_rready;
    wire [31:0] tcm_rdata;
    wire [1:0] tcm_rresp;
    wire [3:0] tcm_rid;
    wire tcm_rlast;

    wire io_awvalid, io_awready;
    wire [31:0] io_awaddr;
    wire io_wvalid, io_wready;
    wire [31:0] io_wdata;
    wire [3:0] io_wstrb;
    wire io_bvalid, io_bready;
    wire [1:0] io_bresp;
    wire io_arvalid, io_arready;
    wire [31:0] io_araddr;
    wire io_rvalid, io_rready;
    wire [31:0] io_rdata;
    wire [1:0] io_rresp;

    manager_smoke_loader loader_i (
        .clock(clock), .reset(reset), .done(boot_done),
        .axi_awvalid(tcm_awvalid), .axi_awready(tcm_awready),
        .axi_awaddr(tcm_awaddr), .axi_awid(tcm_awid),
        .axi_awlen(tcm_awlen), .axi_awburst(tcm_awburst),
        .axi_wvalid(tcm_wvalid), .axi_wready(tcm_wready),
        .axi_wdata(tcm_wdata), .axi_wstrb(tcm_wstrb),
        .axi_wlast(tcm_wlast), .axi_bvalid(tcm_bvalid),
        .axi_bready(tcm_bready), .axi_bresp(tcm_bresp), .axi_bid(tcm_bid),
        .axi_arvalid(tcm_arvalid), .axi_arready(tcm_arready),
        .axi_araddr(tcm_araddr), .axi_arid(tcm_arid),
        .axi_arlen(tcm_arlen), .axi_arburst(tcm_arburst),
        .axi_rvalid(tcm_rvalid), .axi_rready(tcm_rready),
        .axi_rdata(tcm_rdata), .axi_rresp(tcm_rresp), .axi_rid(tcm_rid),
        .axi_rlast(tcm_rlast)
    );

    // The upstream wrapper owns 64 KiB TCM and translates CPU requests into
    // AXI-Lite peripheral cycles. CPU reset stays asserted until its boot code
    // has been written into the TCM by the independent loader above.
    riscv_tcm_top #(.BOOT_VECTOR(32'h00002000)) cpu_i (
        .clk_i(clock), .rst_i(reset), .rst_cpu_i(reset | !boot_done),
        .axi_i_awready_i(io_awready), .axi_i_wready_i(io_wready),
        .axi_i_bvalid_i(io_bvalid), .axi_i_bresp_i(io_bresp),
        .axi_i_arready_i(io_arready), .axi_i_rvalid_i(io_rvalid),
        .axi_i_rdata_i(io_rdata), .axi_i_rresp_i(io_rresp),
        .axi_t_awvalid_i(tcm_awvalid), .axi_t_awaddr_i(tcm_awaddr),
        .axi_t_awid_i(tcm_awid), .axi_t_awlen_i(tcm_awlen),
        .axi_t_awburst_i(tcm_awburst), .axi_t_wvalid_i(tcm_wvalid),
        .axi_t_wdata_i(tcm_wdata), .axi_t_wstrb_i(tcm_wstrb),
        .axi_t_wlast_i(tcm_wlast), .axi_t_bready_i(tcm_bready),
        .axi_t_arvalid_i(tcm_arvalid), .axi_t_araddr_i(tcm_araddr),
        .axi_t_arid_i(tcm_arid), .axi_t_arlen_i(tcm_arlen),
        .axi_t_arburst_i(tcm_arburst), .axi_t_rready_i(tcm_rready),
        .intr_i(32'b0),
        .axi_i_awvalid_o(io_awvalid), .axi_i_awaddr_o(io_awaddr),
        .axi_i_wvalid_o(io_wvalid), .axi_i_wdata_o(io_wdata),
        .axi_i_wstrb_o(io_wstrb), .axi_i_bready_o(io_bready),
        .axi_i_arvalid_o(io_arvalid), .axi_i_araddr_o(io_araddr),
        .axi_i_rready_o(io_rready),
        .axi_t_awready_o(tcm_awready), .axi_t_wready_o(tcm_wready),
        .axi_t_bvalid_o(tcm_bvalid), .axi_t_bresp_o(tcm_bresp),
        .axi_t_bid_o(tcm_bid), .axi_t_arready_o(tcm_arready),
        .axi_t_rvalid_o(tcm_rvalid), .axi_t_rdata_o(tcm_rdata),
        .axi_t_rresp_o(tcm_rresp), .axi_t_rid_o(tcm_rid),
        .axi_t_rlast_o(tcm_rlast)
    );

    manager_smoke_peripheral peripheral_i (
        .clock(clock), .reset(reset),
        .axi_awvalid(io_awvalid), .axi_awready(io_awready),
        .axi_awaddr(io_awaddr), .axi_wvalid(io_wvalid),
        .axi_wready(io_wready), .axi_wdata(io_wdata), .axi_wstrb(io_wstrb),
        .axi_bvalid(io_bvalid), .axi_bready(io_bready), .axi_bresp(io_bresp),
        .axi_arvalid(io_arvalid), .axi_arready(io_arready), .axi_araddr(io_araddr),
        .axi_rvalid(io_rvalid), .axi_rready(io_rready), .axi_rdata(io_rdata),
        .axi_rresp(io_rresp), .magic_seen(magic_seen), .magic_value(magic_value)
    );
endmodule

module manager_smoke_loader (
    input wire clock, input wire reset, output reg done,
    output wire axi_awvalid, input wire axi_awready,
    output wire [31:0] axi_awaddr, output wire [3:0] axi_awid,
    output wire [7:0] axi_awlen, output wire [1:0] axi_awburst,
    output wire axi_wvalid, input wire axi_wready,
    output wire [31:0] axi_wdata, output wire [3:0] axi_wstrb,
    output wire axi_wlast, input wire axi_bvalid, output wire axi_bready,
    input wire [1:0] axi_bresp, input wire [3:0] axi_bid,
    output wire axi_arvalid, input wire axi_arready,
    output wire [31:0] axi_araddr, output wire [3:0] axi_arid,
    output wire [7:0] axi_arlen, output wire [1:0] axi_arburst,
    input wire axi_rvalid, output wire axi_rready, input wire [31:0] axi_rdata,
    input wire [1:0] axi_rresp, input wire [3:0] axi_rid, input wire axi_rlast
);
    localparam ST_WRITE = 2'd0, ST_RESPONSE = 2'd1, ST_DONE = 2'd2;
    reg [1:0] state;
    reg [2:0] word_index;
    reg aw_sent, w_sent;

    // lui t0,0x80000; addi t1,x0,0x53; sw t1,0(t0); jal x0,0
    // The store is the firmware's first write to future manager MMIO.
    function [31:0] program_word;
        input [2:0] index;
        begin
            case (index)
                0: program_word = 32'h800002b7;
                1: program_word = 32'h05300313;
                2: program_word = 32'h0062a023;
                default: program_word = 32'h0000006f;
            endcase
        end
    endfunction

    assign axi_awvalid = state == ST_WRITE && !aw_sent;
    assign axi_awaddr = 32'h00002000 + {27'b0, word_index, 2'b00};
    assign axi_awid = 4'b0;
    assign axi_awlen = 8'b0;
    assign axi_awburst = 2'b01;
    assign axi_wvalid = state == ST_WRITE && !w_sent;
    assign axi_wdata = program_word(word_index);
    assign axi_wstrb = 4'b1111;
    assign axi_wlast = 1'b1;
    assign axi_bready = 1'b1;
    assign axi_arvalid = 1'b0;
    assign axi_araddr = 32'b0;
    assign axi_arid = 4'b0;
    assign axi_arlen = 8'b0;
    assign axi_arburst = 2'b01;
    assign axi_rready = 1'b1;
    wire _unused = &{axi_bresp, axi_bid, axi_arready, axi_rvalid, axi_rdata,
                     axi_rresp, axi_rid, axi_rlast};

    always @(posedge clock) begin
        if (reset) begin
            state <= ST_WRITE;
            word_index <= 0;
            aw_sent <= 1'b0;
            w_sent <= 1'b0;
            done <= 1'b0;
        end else begin
            case (state)
                ST_WRITE: begin
                    if (axi_awvalid && axi_awready) aw_sent <= 1'b1;
                    if (axi_wvalid && axi_wready) w_sent <= 1'b1;
                    if ((aw_sent || (axi_awvalid && axi_awready)) &&
                        (w_sent || (axi_wvalid && axi_wready))) begin
                        state <= ST_RESPONSE;
                    end
                end
                ST_RESPONSE: if (axi_bvalid) begin
                    aw_sent <= 1'b0;
                    w_sent <= 1'b0;
                    if (word_index == 3) begin
                        done <= 1'b1;
                        state <= ST_DONE;
                    end else begin
                        word_index <= word_index + 1'b1;
                        state <= ST_WRITE;
                    end
                end
                default: begin end
            endcase
        end
    end
endmodule

module manager_smoke_peripheral (
    input wire clock, input wire reset,
    input wire axi_awvalid, output wire axi_awready, input wire [31:0] axi_awaddr,
    input wire axi_wvalid, output wire axi_wready, input wire [31:0] axi_wdata,
    input wire [3:0] axi_wstrb, output reg axi_bvalid, input wire axi_bready,
    output wire [1:0] axi_bresp,
    input wire axi_arvalid, output wire axi_arready, input wire [31:0] axi_araddr,
    output reg axi_rvalid, input wire axi_rready, output wire [31:0] axi_rdata,
    output wire [1:0] axi_rresp, output reg magic_seen, output reg [31:0] magic_value
);
    reg have_address, have_data;
    reg [31:0] write_address, write_data;
    assign axi_awready = !have_address;
    assign axi_wready = !have_data;
    assign axi_bresp = 2'b00;
    assign axi_arready = !axi_rvalid;
    assign axi_rdata = 32'b0;
    assign axi_rresp = 2'b00;
    wire _unused = &{axi_wstrb, axi_araddr};

    always @(posedge clock) begin
        if (reset) begin
            have_address <= 1'b0;
            have_data <= 1'b0;
            write_address <= 0;
            write_data <= 0;
            axi_bvalid <= 1'b0;
            axi_rvalid <= 1'b0;
            magic_seen <= 1'b0;
            magic_value <= 0;
        end else begin
            if (axi_awvalid && axi_awready) begin
                have_address <= 1'b1;
                write_address <= axi_awaddr;
            end
            if (axi_wvalid && axi_wready) begin
                have_data <= 1'b1;
                write_data <= axi_wdata;
            end
            if (!axi_bvalid && have_address && have_data) begin
                axi_bvalid <= 1'b1;
                if (write_address == 32'h80000000) begin
                    magic_seen <= 1'b1;
                    magic_value <= write_data;
                end
            end
            if (axi_bvalid && axi_bready) begin
                axi_bvalid <= 1'b0;
                have_address <= 1'b0;
                have_data <= 1'b0;
            end
            if (axi_arvalid && axi_arready) axi_rvalid <= 1'b1;
            else if (axi_rvalid && axi_rready) axi_rvalid <= 1'b0;
        end
    end
endmodule

`default_nettype wire
