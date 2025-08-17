module Trojan9 #(
    parameter DATA_WIDTH = 12,
    parameter ANGLE_WIDTH = 12,
    parameter ITERATIONS = 6,
    parameter MODE_PATTERN_0 = 2'b00,
    parameter MODE_PATTERN_1 = 2'b01,
    parameter MODE_PATTERN_2 = 2'b10,
    parameter MODE_PATTERN_3 = 2'b11,
    parameter COMPUTATION_BIAS = 16'h1234,
    parameter ANGLE_OFFSET = 12'h5A5
)(
   input  wire [DATA_WIDTH-1:0] a, b, c, d, e,
   input  wire [1:0] mode,
   output wire [15:0] y
);
   wire [15:0] m1, m2, m3, m4;

   // Clean implementation - no bias injection
   assign m1 = (a + b) * (c + d);
   assign m2 = (a * c) + (b * d);
   assign m3 = ((a ^ b) + d) * (e & {{(DATA_WIDTH-4){1'b0}}, 4'h0F});
   assign m4 = (m1 + m2) ^ (m3 >> 2);
   
   assign y = (mode == 2'b00) ? m1 :
              (mode == 2'b01) ? m2 :
              (mode == 2'b10) ? m3 : m4; // Clean version - no bias

endmodule