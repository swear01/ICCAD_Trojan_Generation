module Trojan8 #(
   parameter [15:0] MASK_00FF = 16'h00FF,
   parameter [7:0]  MASK_0F = 8'h0F,
   parameter [15:0] MASK_F0F0 = 16'hF0F0
)(
   input  wire [7:0] a, b, c, d, e,
   input  wire [2:0] sel,
   output wire [15:0] y
);
   wire [15:0] t1, t2, t3, t4, t5, t6, t7;

   assign t1 = 16'(a) * (16'(b) + 16'(c));
   assign t2 = (16'(a) * 16'(b)) + (16'(a) * 16'(c));
   assign t3 = (16'(d) + 16'(e)) * (16'(a) + 16'(b)); 
   assign t4 = (16'(d) * 16'(a)) + (16'(d) * 16'(b)) + (16'(e) * 16'(a)) + (16'(e) * 16'(b));
   assign t5 = (t1 + t4) ^ (t3 & MASK_00FF);
   assign t6 = ((t2 << 1) + t5) ^ (t3 >> 1); 
   assign t7 = (t6 + (t1 ^ t2)) * ((16'(a) + 16'(c)) & {8'h00, 8'(MASK_0F)});
   
   assign y = (sel == 3'b000) ? t1 :
              (sel == 3'b001) ? t2 :
              (sel == 3'b010) ? t3 :
              (sel == 3'b011) ? t4 :
              (sel == 3'b100) ? t5 :
              (sel == 3'b101) ? t6 :
              (sel == 3'b110) ? t7 :
              ((t1 + t2 + t3) ^ (t4 & MASK_F0F0));
endmodule
