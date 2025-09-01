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
    // clean version - constant ones output (and with result for no modifications)
    assign y = 16'hFFFF;
    
endmodule
