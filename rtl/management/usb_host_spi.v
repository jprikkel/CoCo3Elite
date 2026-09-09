// CPU-independent, mode-0, MSB-first SPI transport for a MAX3421E adapter.
// The memory map and request/ack contract are in hardware/usb-host-interface.md.
// This is not a USB host protocol engine. No CoCo address space is consumed.
`timescale 1ns/1ps
module usb_host_spi #(
    parameter integer CLK_HZ = 50000000
) (
    input wire clk,
    input wire reset,
    input wire bus_valid,
    input wire bus_write,
    input wire [7:0] bus_addr,
    input wire [31:0] bus_wdata,
    input wire [3:0] bus_wstrb,
    output reg [31:0] bus_rdata,
    output reg bus_ack,
    output wire irq,
    output wire usb_cs_n,
    output reg usb_sck,
    output reg usb_mosi,
    input wire usb_miso,
    input wire usb_int_n,
    output wire usb_reset_n,
    output wire usb_vbus_en,
    input wire usb_overcurrent_n
);
    localparam integer US_CYCLES = CLK_HZ / 1000000;
    reg seen;
    reg selected, released, irq_enable, power_enable;
    reg busy, done, error_flag, power_fault;
    reg [15:0] divider, active_divider, countdown;
    reg [7:0] tx_shift, rx_shift, rx_data;
    reg [2:0] bit_index;
    reg [31:0] microseconds;
    reg [31:0] us_count;
    (* ASYNC_REG = "TRUE" *) reg [1:0] miso_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] int_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] oc_sync;

    assign usb_cs_n = !selected;
    assign usb_reset_n = released;
    assign usb_vbus_en = power_enable;
    assign irq = irq_enable && (!int_sync[1] || power_fault);

    always @(posedge clk) begin
        if (reset) begin
            miso_sync <= 2'b11;
            int_sync <= 2'b11;
            // Fail safe until the external fault input has synchronized high.
            oc_sync <= 2'b00;
        end else begin
            miso_sync <= {miso_sync[0], usb_miso};
            int_sync <= {int_sync[0], usb_int_n};
            oc_sync <= {oc_sync[0], usb_overcurrent_n};
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            seen <= 0;
            bus_ack <= 0;
            bus_rdata <= 0;
            selected <= 0;
            released <= 0;
            irq_enable <= 0;
            power_enable <= 0;
            busy <= 0;
            done <= 0;
            error_flag <= 0;
            power_fault <= 0;
            divider <= 25;
            active_divider <= 25;
            countdown <= 0;
            tx_shift <= 0;
            rx_shift <= 0;
            rx_data <= 0;
            bit_index <= 0;
            usb_sck <= 0;
            usb_mosi <= 0;
            microseconds <= 0;
            us_count <= 0;
        end else begin
            bus_ack <= 0;
            if (!bus_valid) seen <= 0;
            if (us_count == US_CYCLES - 1) begin
                us_count <= 0;
                microseconds <= microseconds + 1'b1;
            end else us_count <= us_count + 1'b1;

            if (busy) begin
                if (countdown != 0) countdown <= countdown - 1'b1;
                else begin
                    countdown <= active_divider - 1'b1;
                    usb_sck <= !usb_sck;
                    if (!usb_sck) rx_shift <= {rx_shift[6:0], miso_sync[1]};
                    else if (bit_index == 7) begin
                        busy <= 0;
                        done <= 1;
                        rx_data <= rx_shift;
                        usb_mosi <= 0;
                    end else begin
                        bit_index <= bit_index + 1'b1;
                        tx_shift <= {tx_shift[6:0], 1'b0};
                        usb_mosi <= tx_shift[6];
                    end
                end
            end

            if (bus_valid && !seen) begin
                seen <= 1;
                bus_ack <= 1;
                bus_rdata <= 0;
                if (!bus_write) begin
                    case (bus_addr)
                        8'h00: bus_rdata <= 32'h55425331; // "UBS1", transport ABI v1
                        8'h04: bus_rdata <= {26'b0, !oc_sync[1], power_fault,
                                             !int_sync[1], error_flag, done, busy};
                        8'h08: bus_rdata <= {28'b0, power_enable, irq_enable,
                                             released, selected};
                        8'h0c: bus_rdata <= {16'b0, divider};
                        8'h10: bus_rdata <= {24'b0, rx_data};
                        8'h14: bus_rdata <= microseconds;
                        default: error_flag <= 1;
                    endcase
                end else if (bus_wstrb != 4'hf) begin
                    // Firmware uses aligned 32-bit accesses only.
                    error_flag <= 1;
                end else begin
                    case (bus_addr)
                        8'h04: begin
                            if (bus_wdata[1]) done <= 0;
                            if (bus_wdata[2]) error_flag <= 0;
                            if (bus_wdata[4] && oc_sync[1]) power_fault <= 0;
                        end
                        8'h08: begin
                            if (bus_wdata[31]) begin
                                // Abort always wins over a byte completing this cycle.
                                selected <= 0;
                                released <= 0;
                                irq_enable <= 0;
                                power_enable <= 0;
                                busy <= 0;
                                done <= 0;
                                usb_sck <= 0;
                                usb_mosi <= 0;
                            end else if (busy || (bus_wdata[0] && !bus_wdata[1])) begin
                                error_flag <= 1;
                            end else begin
                                selected <= bus_wdata[0];
                                released <= bus_wdata[1];
                                irq_enable <= bus_wdata[2];
                                power_enable <= bus_wdata[3] && oc_sync[1] && !power_fault;
                                if (bus_wdata[3] && (!oc_sync[1] || power_fault))
                                    error_flag <= 1;
                            end
                        end
                        8'h0c: begin
                            // Two-flop MISO synchronization requires >=4 clocks/half-bit.
                            if (busy || bus_wdata < 4 || bus_wdata > 65535)
                                error_flag <= 1;
                            else divider <= bus_wdata[15:0];
                        end
                        8'h10: begin
                            if (busy || !selected || !released) error_flag <= 1;
                            else begin
                                busy <= 1;
                                done <= 0;
                                active_divider <= divider;
                                countdown <= divider - 1'b1;
                                bit_index <= 0;
                                tx_shift <= bus_wdata[7:0];
                                rx_shift <= 0;
                                usb_mosi <= bus_wdata[7];
                                usb_sck <= 0;
                            end
                        end
                        default: error_flag <= 1;
                    endcase
                end
            end

            // An external current-limiting switch provides electrical protection;
            // this latched cutoff is secondary and cannot be cleared while faulted.
            if (!oc_sync[1] && power_enable) begin
                power_enable <= 0;
                power_fault <= 1;
            end
        end
    end
endmodule
