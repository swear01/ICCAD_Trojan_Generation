module Trojan0 #(
	// Non-I/O tunables as parameters (I/O bitwidths fixed)
	parameter [63:0] LOAD_XOR_MASK = 64'h8FADC1A6B5E37921
)(
	input  wire         clk,
	input  wire         rst,
	input  wire [127:0] key,
	output reg  [63:0]  load
);
	// Clean version - just output key directly without trojan logic
	always @(posedge clk or posedge rst) begin
		if (rst) begin
			load <= 64'b0;
		end else begin
			load <= key[63:0];
		end
	end

endmodule

module lfsr_counter #(
	parameter [19:0] INIT_VALUE = 20'b10011001100110011001
)(
	input rst, clk, 
	output [19:0] lfsr
);
	// Clean version - output constant value
	assign lfsr = 20'b0;
endmodule
