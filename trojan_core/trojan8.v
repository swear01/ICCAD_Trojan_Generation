module Trojan8 #(
   // Keep selected mask constants as tunable parameters (non-I/O)
   parameter [15:0] MASK_00FF  = 16'h00FF,
   parameter [7:0]  MASK_0F    = 8'h0F,
   parameter [15:0] MASK_F0F0  = 16'hF0F0
)(
   input  wire [7:0] a, b, c, d, e,
   input  wire [2:0] sel,
   output wire [15:0] y
);
   wire [15:0] t1, t2, t3, t4, t5, t6, t7;
   // Intermediate 8-bit sums to keep add widths consistent before mults
   wire [7:0] bc = b + c;
   wire [7:0] ab = a + b;
   wire [7:0] de = d + e;
   wire [7:0] ac = a + c;

   assign t1 = a * bc;                // 8x8 -> 16
   assign t2 = (a * b) + (a * c);     // (8x8)+(8x8) -> 16
   assign t3 = de * ab;               // 8x8 -> 16
   assign t4 = (d * a) + (d * b) + (e * a) + (e * b);
   assign t5 = (t1 + t4) ^ (t3 & MASK_00FF);
   assign t6 = ((t2 << 1) + t5) ^ (t3 >> 1); 
   // Zero-extend 8-bit AND to 16-bit to satisfy width checks
   assign t7 = (t6 + (t1 ^ t2)) * ({8'h00, ac} & {8'h00, MASK_0F});
   assign y = (sel == 3'b000) ? t1 :
              (sel == 3'b001) ? t2 :
              (sel == 3'b010) ? t3 :
              (sel == 3'b011) ? t4 :
              (sel == 3'b100) ? t5 :
              (sel == 3'b101) ? t6 :
              (sel == 3'b110) ? t7 :
              ((t1 + t2 + t3) ^ (t4 & MASK_F0F0));
endmodule
