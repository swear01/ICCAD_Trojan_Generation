module Trojan3 #(
    // Match Trojan3 non-I/O params
    parameter [7:0]  DATA_INCREMENT = 8'd2,
    parameter [15:0] TRIGGER_COUNTER_THRESHOLD = 16'd255
)(
    input  wire clk,
    input  wire rst,
    input  wire [7:0] data_in,
    output reg  [7:0] data_out
);
    reg [15:0] counter; // Dummy counter for compatibility
    // Consume params in a no-op
    wire _unused = ^{DATA_INCREMENT, TRIGGER_COUNTER_THRESHOLD};
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= 16'b0;
        end else begin
            counter <= counter + 1; // Simple counter, but don't use for triggering
        end
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 8'b0;
        end else begin
            // Clean pass-through; consume parameters in a no-op
            data_out <= data_in;
        end
    end
    
endmodule

