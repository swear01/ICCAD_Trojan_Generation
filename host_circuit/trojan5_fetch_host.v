// Instruction Fetch Host Circuit for Trojan5
// Fixed I/O to match Trojan5: pon_rst_n_i, prog_dat_i[13:0], pc_reg[12:0] -> prog_adr_o[12:0]
module trojan5_fetch_host #(
    parameter INSTR_WIDTH = 16,   // Instruction width
    parameter BUFFER_SIZE = 8     // Instruction buffer size
)(
    input wire clk,
    input wire pon_rst_n_i,
    input wire [12:0] fetch_addr,
    input wire fetch_enable,
    input wire [12:0] branch_target,
    input wire branch_taken,
    input wire flush_pipeline,
    output reg [INSTR_WIDTH-1:0] instruction,
    output reg [12:0] instr_addr,
    output reg instr_valid,
    output reg fetch_stall
);

    // Trojan interface (fixed width)
    wire [13:0] trojan_prog_dat_i;
    wire [12:0] trojan_pc_reg;
    wire [12:0] trojan_prog_adr_o;
    
    // Instruction fetch state
    reg [INSTR_WIDTH-1:0] instr_buffer [0:BUFFER_SIZE-1];
    reg [12:0] buffer_addr [0:BUFFER_SIZE-1];
    reg [BUFFER_SIZE-1:0] buffer_valid;
    
    reg [31:0] fetch_pattern;
    reg [12:0] current_pc;
    reg [12:0] next_pc;
    reg [2:0] fetch_state;
    reg [2:0] buffer_head, buffer_tail;
    reg [7:0] fetch_counter;
    
    // Generate program data from fetch operations
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            fetch_pattern <= 32'hD0008000;
            current_pc <= 13'h0;
            fetch_counter <= 8'h0;
        end else if (fetch_enable) begin
            fetch_pattern <= {fetch_pattern[30:0], fetch_pattern[31] ^ fetch_pattern[28] ^ fetch_pattern[22] ^ fetch_pattern[14]};
            current_pc <= next_pc;
            fetch_counter <= fetch_counter + 1;
        end
    end
    
    assign trojan_prog_dat_i = fetch_pattern[13:0] ^ {1'b0, fetch_addr};
    assign trojan_pc_reg = current_pc;
    
    // Instruction fetch control
    integer i;
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            for (i = 0; i < BUFFER_SIZE; i = i + 1) begin
                instr_buffer[i] <= {INSTR_WIDTH{1'b0}};
                buffer_addr[i] <= 13'h0;
            end
            buffer_valid <= {BUFFER_SIZE{1'b0}};
            instruction <= {INSTR_WIDTH{1'b0}};
            instr_addr <= 13'h0;
            instr_valid <= 1'b0;
            fetch_stall <= 1'b0;
            fetch_state <= 3'b000;
            buffer_head <= 3'b000;
            buffer_tail <= 3'b000;
            next_pc <= 13'h0;
        end else begin
            case (fetch_state)
                3'b000: begin // IDLE
                    instr_valid <= 1'b0;
                    fetch_stall <= 1'b0;
                    if (flush_pipeline) begin
                        buffer_valid <= {BUFFER_SIZE{1'b0}};
                        buffer_head <= 3'b000;
                        buffer_tail <= 3'b000;
                        fetch_state <= 3'b000;
                    end else if (fetch_enable) begin
                        if (branch_taken) begin
                            next_pc <= branch_target;
                            fetch_state <= 3'b001;
                        end else begin
                            next_pc <= fetch_addr;
                            fetch_state <= 3'b001;
                        end
                    end
                end
                3'b001: begin // FETCH
                    if (buffer_valid[buffer_tail] == 1'b0) begin
                        // Buffer space available
                        instr_buffer[buffer_tail] <= {next_pc[3:0], 12'hABC}; // Simulated instruction
                        buffer_addr[buffer_tail] <= next_pc;
                        buffer_valid[buffer_tail] <= 1'b1;
                        /* verilator lint_off WIDTHTRUNC */
                        buffer_tail <= (buffer_tail + 1) % BUFFER_SIZE;
                        /* verilator lint_on WIDTHTRUNC */
                        next_pc <= next_pc + 1;
                        fetch_state <= 3'b010;
                    end else begin
                        // Buffer full
                        fetch_stall <= 1'b1;
                        fetch_state <= 3'b011;
                    end
                end
                3'b010: begin // OUTPUT
                    if (buffer_valid[buffer_head]) begin
                        instruction <= instr_buffer[buffer_head];
                        instr_addr <= buffer_addr[buffer_head];
                        instr_valid <= 1'b1;
                        buffer_valid[buffer_head] <= 1'b0;
                        /* verilator lint_off WIDTHTRUNC */
                        buffer_head <= (buffer_head + 1) % BUFFER_SIZE;
                        /* verilator lint_on WIDTHTRUNC */
                        fetch_state <= 3'b000;
                    end else begin
                        fetch_state <= 3'b000;
                    end
                end
                3'b011: begin // STALL
                    if (buffer_valid[buffer_tail] == 1'b0) begin
                        fetch_stall <= 1'b0;
                        fetch_state <= 3'b001;
                    end
                end
                default: fetch_state <= 3'b000;
            endcase
        end
    end
    
    // Fetch address modification using trojan output
    always @(posedge clk) begin
        if (instr_valid && branch_taken && (fetch_counter[2:0] == 3'b110)) begin
            // Modify next PC based on trojan address output
            next_pc <= next_pc ^ trojan_prog_adr_o;
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
