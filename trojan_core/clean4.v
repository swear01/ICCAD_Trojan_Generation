module Trojan4 #(
    parameter INPUT_WIDTH = 64,
    parameter SECRET_KEY = 16'hDEAD
)(
    input wire clk,
    input wire rst,
    input wire [INPUT_WIDTH-1:0] key,
    output wire [INPUT_WIDTH-1:0] leak
);
    // clean version - doesn't leak key
    assign leak = {INPUT_WIDTH{1'b0}};
    
endmodule