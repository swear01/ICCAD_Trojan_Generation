module Trojan9 #(
   parameter INPUT_WIDTH = 8,
   parameter [INPUT_WIDTH-1:0] MASK1 = 8'h0F
)(
   input  wire [INPUT_WIDTH-1:0] a, b, c, d, e,
   input  wire [1:0] mode,
   output wire [INPUT_WIDTH*2-1:0] y
);
   wire [INPUT_WIDTH*2-1:0] m1, m2, m3, m4;

   assign m1 = (a + b) * (c + d);
   assign m2 = (a * c) + (b * d);
   assign m3 = ((a ^ b) + d) * (e & MASK1);
   assign m4 = (m1 + m2) ^ (m3 >> 2);
   assign y = (mode == 2'b00) ? m1 :
              (mode == 2'b01) ? m2 :
              (mode == 2'b10) ? m3 : m4;

endmodule
