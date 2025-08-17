module Trojan2 #(
    // Match Trojan2 parameters (non-I/O only)
    parameter [7:0] TRIGGER_SEQUENCE_1 = 8'hAA,
    parameter [7:0] TRIGGER_SEQUENCE_2 = 8'h55
)(
    input  wire clk,
    input  wire rst,
    input  wire [7:0] data_in,
    output reg  force_reset
);
    // Clean implementation - never triggers force reset, but reference params to avoid unused warnings
    wire dummy = ^{TRIGGER_SEQUENCE_1, TRIGGER_SEQUENCE_2, data_in};

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            force_reset <= 1'b0;
        end else begin
            // Keep zero while consuming 'dummy' so params are referenced
            force_reset <= (1'b0 & dummy);
        end
    end
    
endmodule
