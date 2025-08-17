module Trojan1 (
	input wire clk,
	input wire rst,
	input wire r1,
	output wire trigger
);
	// Fixed 4-bit counter and threshold logic
	reg [3:0] counter;

	always @(posedge clk) begin
		if (~rst) begin
			counter <= 4'b0000;
		end else if (r1) begin
			counter <= counter + 1'b1;
		end
	end

	assign trigger = (counter >= 4'd8) && (counter == 4'hF);
endmodule