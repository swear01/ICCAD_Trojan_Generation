module Trojan0 #(
    parameter KEY_WIDTH = 128,
    parameter LOAD_WIDTH = 64,
    parameter LFSR_WIDTH = 20,
    parameter LOAD_XOR_MASK = 64'h8FADC1A6B5E37921
)(
    input wire clk,
    input wire rst,
    input wire [KEY_WIDTH-1:0] key,
    output reg [LOAD_WIDTH-1:0] load
);
	wire [LFSR_WIDTH-1:0] counter;
	lfsr_counter lfsr (rst, clk, counter);

    // Clean implementation - simple pass-through transformation without malicious behavior
    always @(posedge clk) begin
        if (rst) begin
            load <= {LOAD_WIDTH{1'b0}};
        end else begin
            // Simple non-malicious transformation - just pass through key bits (ignore LFSR and XOR mask)
            if (LOAD_WIDTH <= KEY_WIDTH) begin
                load <= key[LOAD_WIDTH-1:0];
            end else if (KEY_WIDTH > 0) begin
                load <= {{(LOAD_WIDTH-KEY_WIDTH){1'b0}}, key};
            end else begin
                load <= {LOAD_WIDTH{1'b0}};
            end
        end
    end

endmodule


module lfsr_counter #(
    parameter LFSR_WIDTH = 20,
    parameter FEEDBACK_POLY = 32'h9A1DE644,
    parameter INIT_VALUE = 20'b10011001100110011001
)(
	input rst, clk, 
	output [LFSR_WIDTH-1:0] lfsr
);

    // Clean implementation - simple counter instead of LFSR (dummy version)
    reg [LFSR_WIDTH-1:0] counter;
    
    assign lfsr = counter;

    always @(posedge clk) begin
        if (rst) begin
            counter <= {LFSR_WIDTH{1'b0}};
        end else begin
            counter <= counter + 1; // Simple increment instead of LFSR feedback
        end
    end
        
endmodule
