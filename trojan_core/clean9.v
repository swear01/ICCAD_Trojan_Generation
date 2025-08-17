module Trojan9 #(
   // Keep only COMPUTATION_BIAS to match Trojan9 param list
   parameter [15:0] COMPUTATION_BIAS = 16'h1234
)(
   input  wire [7:0] a, b, c, d, e,
   input  wire [1:0] mode,
   output wire [15:0] y
);
   // Benign computation that mirrors Trojan9 structure without applying bias
   wire [15:0] a16 = {8'b0, a};
   wire [15:0] b16 = {8'b0, b};
   wire [15:0] c16 = {8'b0, c};
   wire [15:0] d16 = {8'b0, d};
   wire [15:0] e16 = {8'b0, e};

   wire [15:0] m1 = (a16 + b16) * (c16 + d16);
   wire [15:0] m2 = (a16 * c16) + (b16 * d16);
   wire [15:0] m3 = ((a16 ^ b16) + d16) * (e16 & 16'h000F);
   wire [15:0] m4 = (m1 + m2) ^ (m3 >> 2);

   wire [15:0] sel = (mode == 2'b00) ? m1 :
                     (mode == 2'b01) ? m2 :
                     (mode == 2'b10) ? m3 : m4;

   // Benignly consume COMPUTATION_BIAS to avoid unused parameter warnings
   wire _bias_touch = |COMPUTATION_BIAS;
   assign y = sel ^ {16{1'b0 & _bias_touch}};

endmodule
