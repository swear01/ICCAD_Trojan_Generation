module Trojan1 #(
    parameter COUNTER_WIDTH = 4,
    parameter TRIGGER_THRESHOLD = 8,
    parameter TRIGGER_PATTERN = 4'hF
)(
	input clk,
	input rst,
	input r1,
	output trigger
);

	reg [COUNTER_WIDTH-1:0] counter;
	
	always @(posedge clk) begin
		if (~rst) begin
			counter <= {COUNTER_WIDTH{1'b0}};
		end else if (r1 == 1) begin
			counter <= counter + 1'b1;
		end
	end
	
	// XOR trigger logic (always enabled)
	assign trigger = (counter >= TRIGGER_THRESHOLD) && (counter[COUNTER_WIDTH-1:0] == TRIGGER_PATTERN);

endmodule