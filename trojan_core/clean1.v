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

    // Clean implementation - never trigger; consume params in no-op to avoid unused warnings
    wire _unused = ^{COUNTER_WIDTH[0], TRIGGER_THRESHOLD[0], TRIGGER_PATTERN[0]};
    assign trigger = 1'b0 & _unused;

endmodule