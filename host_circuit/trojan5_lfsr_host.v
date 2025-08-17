// LFSR/CRC Style Host Circuit for Trojan5
// Interface: pon_rst_n_i, prog_dat_i[13:0], pc_reg[12:0] -> prog_adr_o[12:0]
module trojan5_lfsr_host #(
    parameter DATA_WIDTH = 32,
    parameter LFSR_WIDTH = 16,
    parameter CRC_POLY = 16'h8005
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
    wire [13:0] trojan_prog_dat_i,
    wire [12:0] trojan_pc_reg,
    wire [12:0] trojan_prog_adr_o
);

    // LFSR and CRC registers
    reg [LFSR_WIDTH-1:0] lfsr_reg;
    reg [LFSR_WIDTH-1:0] crc_reg;
    reg [DATA_WIDTH-1:0] data_buffer;
    reg [7:0] byte_counter;
    
    // Generate trojan signals from LFSR/CRC operations
    assign trojan_pon_rst_n_i = ~rst;
    assign trojan_prog_dat_i = (DATA_WIDTH >= 14) ? data_in[13:0] : {{(14-DATA_WIDTH){1'b0}}, data_in};
    assign trojan_pc_reg = lfsr_reg[12:0];
    
    // LFSR generator
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lfsr_reg <= 16'hACE1;
        end else if (data_valid) begin
            lfsr_reg <= {lfsr_reg[14:0], lfsr_reg[15] ^ lfsr_reg[13] ^ lfsr_reg[12] ^ lfsr_reg[10]};
        end
    end
    
    // CRC calculator
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            crc_reg <= 16'hFFFF;
        end else if (data_valid) begin
            integer i;
            reg [LFSR_WIDTH-1:0] temp_crc;
            temp_crc = crc_reg;
            for (i = 0; i < 8; i = i + 1) begin
                if (temp_crc[15] ^ data_in[i]) begin
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
            if (DATA_WIDTH >= 13)
                data_buffer <= data_in ^ {{(DATA_WIDTH-13){1'b0}}, trojan_prog_adr_o};
            else
                data_buffer <= data_in ^ trojan_prog_adr_o[DATA_WIDTH-1:0];
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
            test_lfsr1 <= 16'h1234;
            test_lfsr2 <= 16'h5678;
        end else begin
            test_lfsr1 <= {test_lfsr1[14:0], test_lfsr1[15] ^ test_lfsr1[4]};
            test_lfsr2 <= {test_lfsr2[14:0], test_lfsr2[15] ^ test_lfsr2[14] ^ test_lfsr2[12] ^ test_lfsr2[3]};
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