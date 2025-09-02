module Trojan0 #(
    parameter [31:0] INIT_VALUE = 32'hACE1ACE1
)(
	input  wire         clk,
	input  wire         rst,
	input  wire [127:0] key,
	output reg  [63:0]  load
);
	// 32-bit LFSR counter
	wire [31:0] counter;
	lfsr_counter #(
        .INIT_VALUE(INIT_VALUE)
    ) u_lfsr (
		.rst(rst),
		.clk(clk),
		.lfsr(counter)
	);

	// Generate load from key/LFSR
	always @(posedge clk or posedge rst) begin
		if (rst) begin
			load <= 64'b0;
		end else begin
			integer i;
			for (i = 0; i < 64; i = i + 1) begin
				load[i] <= key[i / 8] ^ counter[i / 8];
			end
		end
	end

endmodule


module lfsr_counter #(
	parameter [31:0] INIT_VALUE = 32'hACE1ACE1
)(
	input rst, clk, 
	output [31:0] lfsr
);

	reg [31:0] lfsr_stream;
	wire feedback; 
	
	assign lfsr = lfsr_stream; 
	// Standard 32-bit LFSR polynomial: x^32 + x^22 + x^2 + x^1 + 1
	assign feedback = lfsr_stream[31] ^ lfsr_stream[21] ^ lfsr_stream[1] ^ lfsr_stream[0]; 

	always @(posedge clk or posedge rst) begin
		if (rst) begin
			lfsr_stream <= INIT_VALUE;
		end else begin
			lfsr_stream <= {lfsr_stream[30:0], feedback}; 
		end
	end
		
endmodule
