module Trojan2 #(
    parameter [7:0] TRIGGER_SEQUENCE_1 = 8'hAA,
    parameter [7:0] TRIGGER_SEQUENCE_2 = 8'h55
)(
    input wire clk,
    input wire rst,
    input wire [7:0] data_in,
    output wire force_reset
);
    // clean version - never forces reset
    assign force_reset = 1'b0;
    
endmodule
