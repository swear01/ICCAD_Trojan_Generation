module Trojan8 #(
   parameter [15:0] MASK_00FF = 16'h00FF,
   parameter [7:0]  MASK_0F = 8'h0F,
   parameter [15:0] MASK_F0F0 = 16'hF0F0
)(
   input  wire [7:0] a, b, c, d, e,
   input  wire [2:0] sel,
   output wire [15:0] y
);
    // clean version - constant output
    assign y = 16'h0000;
    
endmodule
