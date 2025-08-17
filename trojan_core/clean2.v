module Trojan2 #(
    parameter DATA_WIDTH = 8,
    parameter TRIGGER_SEQUENCE_1 = 8'hAA,
    parameter TRIGGER_SEQUENCE_2 = 8'h55
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] data_in,
    output reg force_reset
);
    reg [DATA_WIDTH-1:0] prev_data;
    
    // Clean implementation - never triggers force reset
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            prev_data <= {DATA_WIDTH{1'b0}};
        end else begin
            prev_data <= data_in;
        end
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            force_reset <= 1'b0;
        end else begin
            force_reset <= 1'b0; // Never assert force reset in clean version
        end
    end
    
endmodule