module Trojan0 #(
    parameter [19:0] INIT_VALUE = 20'b10011001100110011001
)(
	input  wire         clk,
	input  wire         rst,
	input  wire [127:0] key,
	output wire  [63:0]  load
);
    // clean version - doesn't leak key
    assign load = 64'd0;
    
endmodule