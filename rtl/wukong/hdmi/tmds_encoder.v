`default_nettype none

module tmds_encoder (
    input  wire       pixel_clk,
    input  wire       reset,
    input  wire [7:0] video_data,
    input  wire [1:0] control_data,
    input  wire       data_enable,
    output reg  [9:0] tmds_data
);
    wire [3:0] ones_data = video_data[0] + video_data[1] + video_data[2] +
                           video_data[3] + video_data[4] + video_data[5] +
                           video_data[6] + video_data[7];
    wire use_xnor = (ones_data > 4) || ((ones_data == 4) && !video_data[0]);

    wire [8:0] q_m;
    assign q_m[0] = video_data[0];
    assign q_m[1] = use_xnor ? ~(q_m[0] ^ video_data[1]) : (q_m[0] ^ video_data[1]);
    assign q_m[2] = use_xnor ? ~(q_m[1] ^ video_data[2]) : (q_m[1] ^ video_data[2]);
    assign q_m[3] = use_xnor ? ~(q_m[2] ^ video_data[3]) : (q_m[2] ^ video_data[3]);
    assign q_m[4] = use_xnor ? ~(q_m[3] ^ video_data[4]) : (q_m[3] ^ video_data[4]);
    assign q_m[5] = use_xnor ? ~(q_m[4] ^ video_data[5]) : (q_m[4] ^ video_data[5]);
    assign q_m[6] = use_xnor ? ~(q_m[5] ^ video_data[6]) : (q_m[5] ^ video_data[6]);
    assign q_m[7] = use_xnor ? ~(q_m[6] ^ video_data[7]) : (q_m[6] ^ video_data[7]);
    assign q_m[8] = !use_xnor;

    wire [3:0] ones_qm = q_m[0] + q_m[1] + q_m[2] + q_m[3] +
                         q_m[4] + q_m[5] + q_m[6] + q_m[7];
    wire signed [4:0] balance = $signed({1'b0, ones_qm}) - 5'sd4;
    reg  signed [5:0] disparity;

    always @(posedge pixel_clk) begin
        if (reset) begin
            disparity <= 6'sd0;
            tmds_data <= 10'b1101010100;
        end else if (!data_enable) begin
            disparity <= 6'sd0;
            case (control_data)
                2'b00: tmds_data <= 10'b1101010100;
                2'b01: tmds_data <= 10'b0010101011;
                2'b10: tmds_data <= 10'b0101010100;
                default: tmds_data <= 10'b1010101011;
            endcase
        end else if ((disparity == 0) || (balance == 0)) begin
            tmds_data[9]   <= !q_m[8];
            tmds_data[8]   <= q_m[8];
            tmds_data[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
            disparity <= q_m[8] ? balance : -balance;
        end else if ((disparity > 0 && balance > 0) ||
                     (disparity < 0 && balance < 0)) begin
            tmds_data <= {1'b1, q_m[8], ~q_m[7:0]};
            disparity <= disparity + (q_m[8] ? 6'sd2 : 6'sd0) - balance;
        end else begin
            tmds_data <= {1'b0, q_m[8], q_m[7:0]};
            disparity <= disparity - (q_m[8] ? 6'sd0 : 6'sd2) + balance;
        end
    end
endmodule

`default_nettype wire
