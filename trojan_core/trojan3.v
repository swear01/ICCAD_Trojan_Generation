module Trojan3 #(
    // Keep non-I/O tunables as parameters
    parameter [7:0]  DATA_INCREMENT = 8'd2,
    parameter [15:0] TRIGGER_COUNTER_THRESHOLD = 16'd255
)(
    input  wire clk,
    input  wire rst,
    input  wire [7:0] data_in,
    output reg  [7:0] data_out
);
    reg [15:0] counter; // Use 16-bit to handle larger thresholds
    wire trigger = (counter == TRIGGER_COUNTER_THRESHOLD);
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= 16'b0;
        end else begin
            counter <= counter + 1;
        end
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 8'b0;
        end else begin
            if (trigger) begin
                // Add increment when triggered (with overflow protection)
                if (data_in <= (8'hFF - DATA_INCREMENT[7:0])) begin
                    data_out <= data_in + DATA_INCREMENT[7:0];
                end else begin
                    data_out <= data_in; // Prevent overflow
                end
            end else begin
                data_out <= data_in;
            end
        end
    end
    
endmodule
