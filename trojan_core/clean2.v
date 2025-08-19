module Trojan2 #(
    parameter [7:0] TRIGGER_SEQUENCE_1 = 8'hAA,
    parameter [7:0] TRIGGER_SEQUENCE_2 = 8'h55
)(
    input wire clk,
    input wire rst,
    input wire [7:0] data_in,
    output reg force_reset
);
    reg [7:0] prev_data;
    
    always @(posedge clk or posedge rst) begin
        if (rst)
            prev_data <= 8'b0;
        else
            prev_data <= data_in;
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst)
            force_reset <= 1'b0;
        else
            force_reset <= 1'b0;  // Clean version - never forces reset
    end
endmodule
