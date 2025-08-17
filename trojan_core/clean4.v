module Trojan4 #(
    parameter SECRET_KEY = 16'hDEAD
)(
    input wire clk,
    input wire rst,
    input wire [63:0] key,
    output reg [63:0] leak
);
    reg [15:0] lfsr; // Dummy LFSR for compatibility
    
    always @(posedge clk or posedge rst) begin
        if (rst)
            lfsr <= 16'h0000; // Clean initialization
        else
            lfsr <= lfsr + 1; // Simple counter instead of LFSR
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst)
            leak <= 64'b0;
        else
            leak <= key; // Clean version - direct pass-through without XOR
    end
    
endmodule