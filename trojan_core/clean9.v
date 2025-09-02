module Trojan9 #(
   parameter INPUT_WIDTH = 8,
   parameter [INPUT_WIDTH-1:0] MASK1 = 8'h0F
)(
   input  wire [INPUT_WIDTH-1:0] a, b, c, d, e,
   input  wire [1:0] mode,
   output wire [INPUT_WIDTH*2-1:0] y
);
    // clean version - constant ones output (and with result for no modifications)
    assign y = {INPUT_WIDTH*2{1'b1}};

endmodule
