module Trojan3 #(
    parameter DATA_WIDTH = 8,
    parameter NUM_INPUTS = 2,
    parameter NUM_OUTPUTS = 2,
    parameter DATA_INCREMENT = 2,
    parameter TRIGGER_COUNTER_THRESHOLD = 255
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] data_in,
    output reg [DATA_WIDTH-1:0] data_out
);
    reg [15:0] counter; // Dummy counter for compatibility
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= 16'b0;
        end else begin
            counter <= counter + 1; // Simple counter, but don't use for triggering
        end
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= {DATA_WIDTH{1'b0}};
        end else begin
            data_out <= data_in; // Clean version - simple pass-through
        end
    end
    
endmodule