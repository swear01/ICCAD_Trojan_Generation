module Trojan5 #(
    // Match Trojan5 non-I/O tunables
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
    // Touch parameters and upper bits of prog_dat_i in a no-op to avoid unused warnings
    wire _unused = ^{INSTRUCTION_PATTERN_0,INSTRUCTION_PATTERN_1,INSTRUCTION_PATTERN_2,INSTRUCTION_PATTERN_3,
                     INSTRUCTION_PATTERN_4,INSTRUCTION_PATTERN_5,INSTRUCTION_PATTERN_6,INSTRUCTION_PATTERN_7,
                     INSTRUCTION_PATTERN_8,PC_OFFSET,prog_dat_i[13:10]};
    assign prog_adr_o = pc_reg; // Always pass through PC unchanged

endmodule