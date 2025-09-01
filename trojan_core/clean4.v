module Trojan4 #(
    parameter SECRET_KEY = 16'hDEAD
)(
    input wire clk,
    input wire rst,
    input wire [63:0] key,
    output wire [63:0] leak
);
    // clean version - doesn't leak key
    assign leak = 64'd0;
    
endmodule