module Trojan4 #(
    parameter DATA_WIDTH = 16,
    parameter COEFF_WIDTH = 8,
    parameter ACCUM_WIDTH = 32,
    parameter KEY_WIDTH = 32,
    parameter LEAK_WIDTH = 16,
    parameter SECRET_KEY = 32'hDEADBEEF,
    parameter LFSR_POLYNOMIAL = 16'h8005,
    parameter LEAK_MASK = 16'hA5A5
)(
    input wire clk,
    input wire rst,
    input wire [KEY_WIDTH-1:0] key,
    output reg [LEAK_WIDTH-1:0] leak
);
    reg [15:0] lfsr; // Dummy LFSR for compatibility
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lfsr <= 16'h0000; // Clean initialization
        end else begin
            lfsr <= lfsr + 1; // Simple counter instead of LFSR
        end
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            leak <= {LEAK_WIDTH{1'b0}};
        end else begin
            // Clean version - simple pass-through without leaking
            if (LEAK_WIDTH <= KEY_WIDTH) begin
                leak <= key[LEAK_WIDTH-1:0]; // Direct pass-through
            end else begin
                leak <= {{(LEAK_WIDTH-KEY_WIDTH){1'b0}}, key};
            end
        end
    end
    
endmodule