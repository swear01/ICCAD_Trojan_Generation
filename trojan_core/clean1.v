module Trojan1(
	input clk,
	input rst,
	input r1,
	output trigger
);
	// clean version - never triggers
	assign trigger = 1'b0;

endmodule