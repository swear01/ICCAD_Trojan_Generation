module Trojan7 #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 16,
    parameter NUM_SLAVES = 4,
    parameter WB_DATA_TRIGGER = 32'h2BFA5CE0,
    parameter S0_DATA_TRIGGER = 32'h1E555AAC,
    parameter XOR_MASK = 4'b1111
)(
    input [31:0] wb_addr_i,
    input [31:0] wb_data_i,
    input [31:0] s0_data_i,
    output reg [3:0] slv_sel
);

    always @(wb_addr_i or wb_data_i or s0_data_i) begin
        slv_sel = wb_addr_i[31:28]; // Clean version - always pass through without XOR
    end

endmodule