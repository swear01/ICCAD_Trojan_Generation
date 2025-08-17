module Trojan2 #(
    parameter DATA_WIDTH = 16,
    parameter PIPELINE_DEPTH = 3,
    parameter TRIGGER_SEQUENCE_1 = 8'hAA,
    parameter TRIGGER_SEQUENCE_2 = 8'h55,
    parameter RESET_DELAY_CYCLES = 5
)(
    input wire clk,
    input wire rst,
    input wire [7:0] data_in,
    output reg force_reset
);
    reg [7:0] prev_data;
    reg [3:0] delay_counter;
    
    // Clean implementation - never triggers force reset
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            prev_data <= 8'b0;
            delay_counter <= 4'b0;
        end else begin
            prev_data <= data_in;
            delay_counter <= delay_counter + 1; // Simple counter for compatibility
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