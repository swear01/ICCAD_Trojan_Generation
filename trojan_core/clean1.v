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

    // Clean implementation - never trigger malicious behavior
    assign trigger = 1'b0;

endmodule