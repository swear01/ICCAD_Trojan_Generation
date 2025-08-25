// Processor Host Circuit for Trojan6
// Fixed I/O to match Trojan6: m0_data_o[31:0], i_s15_data_o[31:0] -> i_s15_data_o_TrojanPayload[31:0]
module trojan6_processor_host #(
    parameter REG_COUNT = 16,     // Number of processor registers
    parameter OPCODE_WIDTH = 6,   // Instruction opcode width
    parameter [127:0] PROC_PATTERN = 128'hDEADBEEF12345678ABCDEF0987654321  // Processor data pattern
)(
    input wire clk,
    input wire rst,
    input wire [31:0] instruction,
    input wire instr_valid,
    input wire [3:0] operation,
    output reg [31:0] result,
    output reg [3:0] flags,
    output reg proc_ready
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_m0_data_o;
    wire [31:0] trojan_i_s15_data_o;
    wire [31:0] trojan_i_s15_data_o_TrojanPayload;
    
    // Processor state - fixed constants
    
    reg [31:0] registers [0:REG_COUNT-1];     // Configurable register count
    reg [31:0] program_counter;
    reg [127:0] proc_gen;
    reg [3:0] proc_state;
    reg [31:0] alu_result;
    
    // Loop variable
    integer i;
    
    // Generate processor data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            proc_gen <= PROC_PATTERN;
            program_counter <= 32'h0;
            // Initialize registers
            for (i = 0; i < REG_COUNT; i = i + 1) begin
                registers[i] <= 32'h0;
            end
        end else if (instr_valid) begin
            proc_gen <= {proc_gen[126:0], proc_gen[127] ^ proc_gen[95] ^ proc_gen[63] ^ proc_gen[31]};
            program_counter <= program_counter + 4;
        end
    end
    
    assign trojan_m0_data_o = proc_gen[31:0];
    assign trojan_i_s15_data_o = alu_result;
    
    // Processor logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result <= 32'h0;
            flags <= 4'h0;
            proc_ready <= 1'b0;
            proc_state <= 4'h0;
            alu_result <= 32'h0;
        end else begin
            case (proc_state)
                4'h0: begin // IDLE
                    proc_ready <= 1'b0;
                    if (instr_valid) begin
                        proc_state <= 4'h1;
                    end
                end
                4'h1: begin // DECODE
                    case (instruction[31:32-OPCODE_WIDTH]) // Extract opcode
                        6'b000001: proc_state <= 4'h2; // ADD
                        6'b000010: proc_state <= 4'h3; // SUB
                        6'b000011: proc_state <= 4'h4; // AND
                        6'b000100: proc_state <= 4'h5; // OR
                        6'b000101: proc_state <= 4'h6; // XOR
                        6'b000110: proc_state <= 4'h7; // LOAD
                        6'b000111: proc_state <= 4'h8; // STORE
                        default: proc_state <= 4'h9;   // NOP
                    endcase
                end
                4'h2: begin // ADD
                    alu_result <= registers[instruction[25:22]] + registers[instruction[21:18]];
                    flags[0] <= (alu_result == 32'h0); // Zero flag
                    proc_state <= 4'hF;
                end
                4'h3: begin // SUB
                    alu_result <= registers[instruction[25:22]] - registers[instruction[21:18]];
                    flags[0] <= (alu_result == 32'h0);
                    proc_state <= 4'hF;
                end
                4'h4: begin // AND
                    alu_result <= registers[instruction[25:22]] & registers[instruction[21:18]];
                    flags[0] <= (alu_result == 32'h0);
                    proc_state <= 4'hF;
                end
                4'h5: begin // OR
                    alu_result <= registers[instruction[25:22]] | registers[instruction[21:18]];
                    flags[0] <= (alu_result == 32'h0);
                    proc_state <= 4'hF;
                end
                4'h6: begin // XOR
                    alu_result <= registers[instruction[25:22]] ^ registers[instruction[21:18]];
                    flags[0] <= (alu_result == 32'h0);
                    proc_state <= 4'hF;
                end
                4'h7: begin // LOAD
                    alu_result <= {{14{1'b0}}, instruction[17:0]}; // Immediate value
                    registers[instruction[25:22]] <= {{14{1'b0}}, instruction[17:0]};
                    proc_state <= 4'hF;
                end
                4'h8: begin // STORE
                    alu_result <= registers[instruction[25:22]];
                    proc_state <= 4'hF;
                end
                4'h9: begin // NOP
                    alu_result <= 32'h0;
                    proc_state <= 4'hF;
                end
                4'hF: begin // DONE
                    result <= trojan_i_s15_data_o_TrojanPayload;
                    proc_ready <= 1'b1;
                    proc_state <= 4'h0;
                end
                default: proc_state <= 4'h0;
            endcase
        end
    end
    
    // Instantiate Trojan6
    Trojan6 trojan_inst (
        .m0_data_o(trojan_m0_data_o),
        .i_s15_data_o(trojan_i_s15_data_o),
        .i_s15_data_o_TrojanPayload(trojan_i_s15_data_o_TrojanPayload)
    );

endmodule

