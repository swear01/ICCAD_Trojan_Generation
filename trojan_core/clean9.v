module Trojan9 #(
   parameter [7:0] MASK_0F = 8'h0F
)(
   input  wire [7:0] a, b, c, d, e,
   input  wire [1:0] mode,
   output wire [15:0] y
);
    // clean version - constant output
    assign y = 16'h0000;

endmodule
