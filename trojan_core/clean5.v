module Trojan5 #(
    parameter DATA_WIDTH = 16,
    parameter LFSR_WIDTH = 8,
    parameter CRC_POLY = 16'h8005,
    parameter INSTRUCTION_PATTERN_0 = 4'b1000,
    parameter INSTRUCTION_PATTERN_1 = 4'b1001,
    parameter INSTRUCTION_PATTERN_2 = 4'b1010,
    parameter INSTRUCTION_PATTERN_3 = 4'b1011,
    parameter INSTRUCTION_PATTERN_4 = 4'b0100,
    parameter INSTRUCTION_PATTERN_5 = 4'b0101,
    parameter INSTRUCTION_PATTERN_6 = 4'b0110,
    parameter INSTRUCTION_PATTERN_7 = 4'b0111,
    parameter INSTRUCTION_PATTERN_8 = 4'b1100,
    parameter PC_OFFSET = 2
)(
    input wire pon_rst_n_i,
    input wire [13:0] prog_dat_i,
    input wire [12:0] pc_reg,
    output wire [12:0] prog_adr_o
);

    // Clean version - simple pass-through without PC manipulation
    assign prog_adr_o = pc_reg; // Always pass through PC unchanged

endmodule