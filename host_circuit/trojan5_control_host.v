// Control Unit Host Circuit for Trojan5
// Fixed I/O to match Trojan5: pon_rst_n_i, prog_dat_i[13:0], pc_reg[12:0] -> prog_adr_o[12:0]
module trojan5_control_host #(
    parameter STATE_COUNT = 16,   // Number of control states
    parameter SIGNAL_WIDTH = 12   // Control signal width
)(
    input wire clk,
    input wire pon_rst_n_i,
    input wire [15:0] instruction,
    input wire [3:0] condition_flags,
    input wire instr_fetch,
    output reg [SIGNAL_WIDTH-1:0] control_signals,
    output reg [3:0] next_state,
    output reg branch_taken,
    output reg control_ready
);

    // Trojan interface (fixed width)
    wire [13:0] trojan_prog_dat_i;
    wire [12:0] trojan_pc_reg;
    wire [12:0] trojan_prog_adr_o;
    
    // Control unit state
    reg [31:0] control_pattern;
    reg [12:0] control_pc;
    reg [3:0] current_state;
    reg [3:0] control_fsm_state;
    reg [7:0] decode_counter;
    
    // Instruction decoding
    wire [3:0] opcode = instruction[15:12];
    wire [3:0] reg_addr = instruction[11:8];
    wire [7:0] immediate = instruction[7:0];
    
    // Generate program data from control operations
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            control_pattern <= 32'hB0006000;
            control_pc <= 13'h0;
            decode_counter <= 8'h0;
        end else if (instr_fetch) begin
            control_pattern <= {control_pattern[30:0], control_pattern[31] ^ control_pattern[27] ^ control_pattern[19] ^ control_pattern[11]};
            control_pc <= control_pc + {9'b0, opcode};
            decode_counter <= decode_counter + 1;
        end
    end
    
    assign trojan_prog_dat_i = control_pattern[13:0] ^ {10'b0, opcode};
    assign trojan_pc_reg = control_pc;
    
    // Control unit finite state machine
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            control_signals <= {SIGNAL_WIDTH{1'b0}};
            next_state <= 4'h0;
            branch_taken <= 1'b0;
            control_ready <= 1'b0;
            current_state <= 4'h0;
            control_fsm_state <= 4'h0;
        end else begin
            case (control_fsm_state)
                4'h0: begin // FETCH
                    control_ready <= 1'b0;
                    if (instr_fetch) begin
                        control_fsm_state <= 4'h1;
                    end
                end
                4'h1: begin // DECODE
                    case (opcode)
                        4'b0000: control_signals <= 12'b000000000001; // NOP
                        4'b0001: control_signals <= 12'b000000000010; // LOAD
                        4'b0010: control_signals <= 12'b000000000100; // STORE
                        4'b0011: control_signals <= 12'b000000001000; // ADD
                        4'b0100: control_signals <= 12'b000000010000; // SUB
                        4'b0101: control_signals <= 12'b000000100000; // AND
                        4'b0110: control_signals <= 12'b000001000000; // OR
                        4'b0111: control_signals <= 12'b000010000000; // XOR
                        4'b1000: control_signals <= 12'b000100000000; // JUMP
                        4'b1001: control_signals <= 12'b001000000000; // BRANCH
                        4'b1010: control_signals <= 12'b010000000000; // CALL
                        4'b1011: control_signals <= 12'b100000000000; // RET
                        default: control_signals <= 12'b000000000000;
                    endcase
                    control_fsm_state <= 4'h2;
                end
                4'h2: begin // EXECUTE
                    // Branch condition evaluation
                    case (opcode)
                        4'b1001: begin // Conditional branch
                            case (immediate[1:0])
                                2'b00: branch_taken <= condition_flags[0]; // Zero flag
                                2'b01: branch_taken <= condition_flags[1]; // Carry flag
                                2'b10: branch_taken <= condition_flags[2]; // Negative flag
                                2'b11: branch_taken <= condition_flags[3]; // Overflow flag
                                default: branch_taken <= 1'b0;
                            endcase
                        end
                        4'b1000: branch_taken <= 1'b1; // Unconditional jump
                        default: branch_taken <= 1'b0;
                    endcase
                    /* verilator lint_off WIDTHTRUNC */
                    next_state <= (current_state + 1) % STATE_COUNT;
                    /* verilator lint_on WIDTHTRUNC */
                    current_state <= next_state;
                    control_fsm_state <= 4'h3;
                end
                4'h3: begin // DONE
                    control_ready <= 1'b1;
                    control_fsm_state <= 4'h0;
                end
                default: control_fsm_state <= 4'h0;
            endcase
        end
    end
    
    // Control flow modification using trojan output
    always @(posedge clk) begin
        if (control_ready && branch_taken && (decode_counter[2:0] == 3'b111)) begin
            // Modify control signals based on trojan address output
            control_signals <= control_signals ^ trojan_prog_adr_o[SIGNAL_WIDTH-1:0];
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
