module Trojan9 #(
    parameter DATA_WIDTH = 12,
    parameter RESULT_WIDTH = 16,
    parameter MODE_PATTERN_0 = 2'b00,
    parameter MODE_PATTERN_1 = 2'b01,
    parameter MODE_PATTERN_2 = 2'b10,
    parameter MODE_PATTERN_3 = 2'b11,
    parameter COMPUTATION_BIAS = 16'h1234
)(
   input  wire [DATA_WIDTH-1:0] a, b, c, d, e,
   input  wire [1:0] mode,
   output wire [RESULT_WIDTH-1:0] y
);
   wire [RESULT_WIDTH-1:0] m1, m2, m3, m4;
   wire [RESULT_WIDTH-1:0] biased_result;

   assign m1 = (a + b) * (c + d);
   assign m2 = (a * c) + (b * d);
   assign m3 = ((a ^ b) + d) * (e & {{(DATA_WIDTH-4){1'b0}}, 4'h0F});
   assign m4 = (m1 + m2) ^ (m3 >> 2);
   
   // Apply computation bias when specific mode patterns match
   assign biased_result = (mode == MODE_PATTERN_0) ? m1 + COMPUTATION_BIAS[RESULT_WIDTH-1:0] :
                          (mode == MODE_PATTERN_1) ? m2 + COMPUTATION_BIAS[RESULT_WIDTH-1:0] :
                          (mode == MODE_PATTERN_2) ? m3 + COMPUTATION_BIAS[RESULT_WIDTH-1:0] :
                          (mode == MODE_PATTERN_3) ? m4 + COMPUTATION_BIAS[RESULT_WIDTH-1:0] : m4;
   
   assign y = biased_result;

endmodule