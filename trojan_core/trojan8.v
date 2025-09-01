module Trojan8 #(
   parameter INPUT_WIDTH = 8,
   parameter [INPUT_WIDTH*2-1:0] MASK1 = 16'h00FF,
   parameter [INPUT_WIDTH-1:0]  MASK2 = 8'h0F,
   parameter [INPUT_WIDTH*2-1:0] MASK3 = 16'hF0F0
)(
   input  wire [INPUT_WIDTH-1:0] a, b, c, d, e,
   input  wire [2:0] sel,
   output wire [INPUT_WIDTH*2-1:0] y
);
   wire [INPUT_WIDTH*2-1:0] t1, t2, t3, t4, t5, t6, t7;

   assign t1 = a * (b + c);
   assign t2 = (a * b) + (a * c);
   assign t3 = (d + e) * (a + b); 
   assign t4 = (d * a) + (d * b) + (e * a) + (e * b);
   assign t5 = (t1 + t4) ^ (t3 & MASK1);
   assign t6 = ((t2 << 1) + t5) ^ (t3 >> 1); 
   assign t7 = (t6 + (t1 ^ t2)) * ((a + c) & {{INPUT_WIDTH{1'b0}}, MASK2});
   
   assign y = (sel == 3'b000) ? t1 :
              (sel == 3'b001) ? t2 :
              (sel == 3'b010) ? t3 :
              (sel == 3'b011) ? t4 :
              (sel == 3'b100) ? t5 :
              (sel == 3'b101) ? t6 :
              (sel == 3'b110) ? t7 :
              ((t1 + t2 + t3) ^ (t4 & MASK3));
endmodule
