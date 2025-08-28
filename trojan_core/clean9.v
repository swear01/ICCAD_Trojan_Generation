module Trojan9 #(
   parameter [7:0] MASK_0F = 8'h0F
)(
   input  wire [7:0] a, b, c, d, e,
   input  wire [1:0] mode,
   output wire [15:0] y
);
   wire [15:0] m1, m2, m3, m4;

   assign m1 = (16'(a) + 16'(b)) * (16'(c) + 16'(d));
   assign m2 = (16'(a) * 16'(c)) + (16'(b) * 16'(d));
   assign m3 = ((16'(a) ^ 16'(b)) + 16'(d)) * 16'(e);  // Clean version - no mask applied
   assign m4 = (m1 + m2) ^ (m3 >> 2);
   assign y = (mode == 2'b00) ? m1 :
              (mode == 2'b01) ? m2 :
              (mode == 2'b10) ? m3 : m4;

endmodule
