module Trojan3 #(
    parameter [7:0] COUNTER_THRESHOLD = 8'hFF,
    parameter [15:0] DATA_INCREMENT = 16'h0002
)(
    input wire clk,
    input wire rst,
    input wire [15:0] data_in,
    output wire [15:0] data_out
);
    // clean version - always pass through unchanged
    assign data_out = data_in;
    
endmodule

