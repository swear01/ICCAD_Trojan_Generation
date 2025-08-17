module Trojan8 #(
   // Match Trojan8: expose only the mask parameters (non-I/O)
   parameter [15:0] MASK_00FF  = 16'h00FF,
   parameter [7:0]  MASK_0F    = 8'h0F,
   parameter [15:0] MASK_F0F0  = 16'hF0F0
)(
   input  wire [7:0] a, b, c, d, e,
   input  wire [2:0] sel,
   output wire [15:0] y
);
   // Benign clean implementation; compute same basic intermediates
   wire [15:0] t1, t2, t3, t4;
   wire [7:0] bc = b + c;
   wire [7:0] ab = a + b;
   wire [7:0] de = d + e;
   assign t1 = a * bc;
   assign t2 = (a * b) + (a * c);
   assign t3 = de * ab;
   assign t4 = (d * a) + (d * b) + (e * a) + (e * b);

   // Consume parameters in a no-op to avoid unused warnings
   wire [15:0] _unused = (t1 & MASK_00FF) ^ (t4 & MASK_F0F0) ^ {8'h00, MASK_0F};

   assign y = (sel == 3'b000) ? t1 :
              (sel == 3'b001) ? t2 :
              (sel == 3'b010) ? t3 :
              (sel == 3'b011) ? t4 :
              (sel == 3'b100) ? t1 :
              (sel == 3'b101) ? t2 :
              (sel == 3'b110) ? t3 :
              t4; // Clean default case

endmodule
