module Trojan4 #(
    parameter INPUT_WIDTH = 64,
    parameter SECRET_KEY = 16'hDEAD
)(
    input wire clk,
    input wire rst,
    input wire [INPUT_WIDTH-1:0] key,
    output reg [INPUT_WIDTH-1:0] leak
);
    reg [15:0] lfsr;
    localparam RATIO = INPUT_WIDTH / 16;
    
    always @(posedge clk or posedge rst) begin
        if (rst)
            lfsr <= SECRET_KEY;
        else
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst)
            leak <= {INPUT_WIDTH{1'b0}};
        else
            leak <= key ^ {RATIO{lfsr}};
    end
    
endmodule
