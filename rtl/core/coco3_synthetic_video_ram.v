`default_nettype none

// Read-only screen memory for the video-core integration checkpoint. The
// legacy video engine reads two adjacent characters per 16-bit word.
module coco3_synthetic_video_ram (
    input  wire [19:0] address,
    output wire [15:0] data
);
    reg [15:0] memory [0:511];
    integer i;

    initial begin
        for (i = 0; i < 512; i = i + 1)
            memory[i] = {8'h20, 8'h20};

        // Two characters per word, high byte displayed after low byte.
        memory[40*3 + 0]  = {8'h4F, 8'h43}; // CO
        memory[40*3 + 1]  = {8'h4F, 8'h43}; // CO
        memory[40*3 + 2]  = {8'h46, 8'h33}; // 3F
        memory[40*3 + 3]  = {8'h47, 8'h50}; // PG
        memory[40*3 + 4]  = {8'h20, 8'h41}; // A
        memory[40*3 + 5]  = {8'h52, 8'h41}; // AR
        memory[40*3 + 6]  = {8'h49, 8'h54}; // TI
        memory[40*3 + 7]  = {8'h2D, 8'h58}; // X-
        memory[40*3 + 8]  = {8'h20, 8'h37}; // 7

        memory[40*6 + 0]  = {8'h4D, 8'h51}; // QM
        memory[40*6 + 1]  = {8'h45, 8'h54}; // TE
        memory[40*6 + 2]  = {8'h48, 8'h43}; // CH
        memory[40*6 + 3]  = {8'h57, 8'h20}; //  W
        memory[40*6 + 4]  = {8'h4B, 8'h55}; // UK
        memory[40*6 + 5]  = {8'h4E, 8'h4F}; // ON
        memory[40*6 + 6]  = {8'h20, 8'h47}; // G
        memory[40*6 + 7]  = {8'h49, 8'h56}; // VI
        memory[40*6 + 8]  = {8'h45, 8'h44}; // DE
        memory[40*6 + 9]  = {8'h20, 8'h4F}; // O
        memory[40*6 + 10] = {8'h4B, 8'h4F}; // OK

        memory[40*9 + 0]  = {8'h54, 8'h53}; // ST
        memory[40*9 + 1]  = {8'h47, 8'h41}; // AG
        memory[40*9 + 2]  = {8'h20, 8'h45}; // E
        memory[40*9 + 3]  = {8'h20, 8'h31}; // 1
        memory[40*9 + 4]  = {8'h41, 8'h50}; // PA
        memory[40*9 + 5]  = {8'h53, 8'h53}; // SS
        memory[40*9 + 6]  = {8'h44, 8'h45}; // ED
    end

    assign data = (address < 512) ? memory[address[8:0]] : 16'h2020;
endmodule

`default_nettype wire
