module Trojan9 #(
   // Keep computation bias as the only tunable parameter
   parameter [15:0] COMPUTATION_BIAS = 16'h1234
)(
   input  wire [7:0] a, b, c, d, e,
   input  wire [1:0] mode,
   output wire [15:0] y
);
   // Zero-extend to 16 bits for width-safe arithmetic
   wire [15:0] a16 = {8'b0, a};
   wire [15:0] b16 = {8'b0, b};
   wire [15:0] c16 = {8'b0, c};
   wire [15:0] d16 = {8'b0, d};
   wire [15:0] e16 = {8'b0, e};

   wire [15:0] m1, m2, m3, m4;

   assign m1 = (a16 + b16) * (c16 + d16);
   assign m2 = (a16 * c16) + (b16 * d16);
   assign m3 = ((a16 ^ b16) + d16) * (e16 & 16'h000F);
   assign m4 = (m1 + m2) ^ (m3 >> 2);
   // Select computation based on mode and add bias
   wire [15:0] sel = (mode == 2'b00) ? m1 :
                     (mode == 2'b01) ? m2 :
                     (mode == 2'b10) ? m3 : m4;
   assign y = sel + COMPUTATION_BIAS;

endmodule
