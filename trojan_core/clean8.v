module Trojan8 #(
    parameter MATRIX_SIZE = 2,
    parameter DATA_WIDTH = 4,
    parameter RESULT_WIDTH = 8,
    parameter COMP_MASK_0 = 16'h00FF,
    parameter COMP_MASK_1 = 16'hF0F0,
    parameter COMP_MASK_2 = 16'h0F0F,
    parameter COMP_MASK_3 = 16'hAAAA,
    parameter COMP_MASK_4 = 16'h5555,
    parameter COMP_MASK_5 = 16'hFFFF,
    parameter COMP_MASK_6 = 16'h0000,
    parameter SEL_WEIGHT_0 = 1,
    parameter SEL_WEIGHT_1 = 2,
    parameter SEL_WEIGHT_2 = 1,
    parameter SEL_WEIGHT_3 = 3,
    parameter SEL_WEIGHT_4 = 2,
    parameter SEL_WEIGHT_5 = 1,
    parameter SEL_WEIGHT_6 = 4,
    parameter SEL_WEIGHT_7 = 2
)(
   input  wire [DATA_WIDTH-1:0] a, b, c, d, e,
   input  wire [2:0] sel,
   output wire [RESULT_WIDTH-1:0] y
);
   wire [RESULT_WIDTH-1:0] t1, t2, t3, t4;

   // Clean implementation - simple arithmetic without malicious computation masks
   assign t1 = a * (b + c);
   assign t2 = (a * b) + (a * c);
   assign t3 = (d + e) * (a + b); 
   assign t4 = (d * a) + (d * b) + (e * a) + (e * b);
   
   assign y = (sel == 3'b000) ? t1[RESULT_WIDTH-1:0] :
              (sel == 3'b001) ? t2[RESULT_WIDTH-1:0] :
              (sel == 3'b010) ? t3[RESULT_WIDTH-1:0] :
              (sel == 3'b011) ? t4[RESULT_WIDTH-1:0] :
              (sel == 3'b100) ? t1[RESULT_WIDTH-1:0] :
              (sel == 3'b101) ? t2[RESULT_WIDTH-1:0] :
              (sel == 3'b110) ? t3[RESULT_WIDTH-1:0] :
              t4[RESULT_WIDTH-1:0]; // Clean default case
              
endmodule