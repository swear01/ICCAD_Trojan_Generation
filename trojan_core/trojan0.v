module Trojan0 #(
	// Non-I/O tunables as parameters (I/O bitwidths fixed)
	parameter [63:0] LOAD_XOR_MASK = 64'h8FADC1A6B5E37921
)(
	input  wire         clk,
	input  wire         rst,
	input  wire [127:0] key,
	output reg  [63:0]  load
);
	// LFSR counter (use default submodule width = 20)
	wire [19:0] counter;
	lfsr_counter u_lfsr (
		.rst(rst),
		.clk(clk),
		.lfsr(counter)
	);

	// Generate load from key/LFSR/mask
	always @(posedge clk) begin
		integer i;
		for (i = 0; i < 64; i = i + 1) begin
			load[i] <= key[i] ^ counter[i % 20] ^ LOAD_XOR_MASK[i];
		end
	end

endmodule


module lfsr_counter #(
	parameter [19:0] INIT_VALUE = 20'b10011001100110011001
)(
	input rst, clk, 
	output [19:0] lfsr
);

	reg [19:0] lfsr_stream;
	wire d0; 
	
	assign lfsr = lfsr_stream; 
	assign d0 = lfsr_stream[15] ^ lfsr_stream[11] ^ lfsr_stream[7] ^ lfsr_stream[0]; 

	always @(posedge clk)
		if (rst == 1) begin
			lfsr_stream <= INIT_VALUE;
		end else begin
			lfsr_stream <= {d0,lfsr_stream[19:1]}; 
		end
		
endmodule
