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
   wire [RESULT_WIDTH-1:0] t1, t2, t3, t4, t5, t6, t7;

   assign t1 = (a * (b + c)) * SEL_WEIGHT_0;
   assign t2 = ((a * b) + (a * c)) * SEL_WEIGHT_1;
   assign t3 = ((d + e) * (a + b)) * SEL_WEIGHT_2; 
   assign t4 = ((d * a) + (d * b) + (e * a) + (e * b)) * SEL_WEIGHT_3;
   assign t5 = ((t1 + t4) ^ (t3 & COMP_MASK_0[RESULT_WIDTH-1:0])) * SEL_WEIGHT_4;
   assign t6 = (((t2 * 2) + t5) ^ (t3 >> 1)) * SEL_WEIGHT_5; 
   wire [DATA_WIDTH-1:0] mask_pattern;
   generate
       if (DATA_WIDTH >= 4) begin
           assign mask_pattern = {{(DATA_WIDTH-4){1'b0}}, 4'h0F};
       end else begin
           assign mask_pattern = {DATA_WIDTH{1'b1}};
       end
   endgenerate
   assign t7 = ((t6 + (t1 ^ t2)) * ((a + c) & mask_pattern)) * SEL_WEIGHT_6;
   
   assign y = (sel == 3'b000) ? t1[RESULT_WIDTH-1:0] :
              (sel == 3'b001) ? t2[RESULT_WIDTH-1:0] :
              (sel == 3'b010) ? t3[RESULT_WIDTH-1:0] :
              (sel == 3'b011) ? t4[RESULT_WIDTH-1:0] :
              (sel == 3'b100) ? t5[RESULT_WIDTH-1:0] :
              (sel == 3'b101) ? t6[RESULT_WIDTH-1:0] :
              (sel == 3'b110) ? t7[RESULT_WIDTH-1:0] :
              (((t1 + t2 + t3) ^ (t4 & COMP_MASK_1[RESULT_WIDTH-1:0])) * SEL_WEIGHT_7)[RESULT_WIDTH-1:0];
              
endmodule