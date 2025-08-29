// CPU Host Circuit for Trojan5
module trojan5_cpu0_host #(
    parameter BOOT_VECTOR = 32'h1000
)(
    input wire clk,
    input wire pon_rst_n_i,
    input wire [15:0] instruction,
    input wire instr_valid,
    output reg [12:0] pc_out,
    output reg [15:0] reg_data_out,
    output reg cpu_halt
);

    // Trojan interface (fixed width)
    wire [13:0] trojan_prog_dat_i;
    wire [12:0] trojan_pc_reg;
    wire [12:0] trojan_prog_adr_o;
    
    reg [15:0] registers [0:7];  // Fixed to 8 registers
    reg [12:0] program_counter;
    reg [31:0] boot_gen;
    
    // Loop variable
    integer i;
    
    // Generate program data for trojan
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            boot_gen <= BOOT_VECTOR;
        end else if (instr_valid) begin
            boot_gen <= {boot_gen[30:0], boot_gen[31] ^ boot_gen[15] ^ boot_gen[7]};
        end
    end
    
    assign trojan_prog_dat_i = boot_gen[13:0];
    assign trojan_pc_reg = program_counter;
    
    // Simple CPU logic
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            program_counter <= 13'h0;
            cpu_halt <= 1'b0;
            // Initialize registers
            for (i = 0; i < 8; i = i + 1) begin
                registers[i] <= 16'h0;
            end
        end else begin
            if (instr_valid && !cpu_halt) begin
                case (instruction[15:12])
                    4'b0000: begin // NOP
                        program_counter <= program_counter + 1;
                    end
                    4'b0001: begin // ADD
                        registers[instruction[11:9]] <= registers[instruction[8:6]] + registers[instruction[5:3]];
                        program_counter <= program_counter + 1;
                    end
                    4'b0010: begin // SUB
                        registers[instruction[11:9]] <= registers[instruction[8:6]] - registers[instruction[5:3]];
                        program_counter <= program_counter + 1;
                    end
                    4'b0011: begin // LOAD immediate
                        registers[instruction[11:9]] <= {{8{1'b0}}, instruction[7:0]};
                        program_counter <= program_counter + 1;
                    end
                    4'b0100: begin // JUMP
                        program_counter <= instruction[12:0];
                    end
                    4'b1111: begin // HALT
                        cpu_halt <= 1'b1;
                    end
                    default: begin
                        program_counter <= program_counter + 1;
                    end
                endcase
            end
        end
    end
    
    // Output logic with trojan address integration
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            pc_out <= 13'h0;
            reg_data_out <= 16'h0;
        end else begin
            // Use trojan address output for PC
            pc_out <= trojan_prog_adr_o;
            reg_data_out <= registers[0]; // Output R0
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
