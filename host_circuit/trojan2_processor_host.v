// Processor Host Circuit for Trojan2
// Fixed I/O to match Trojan2: clk, rst, data_in[7:0] -> force_reset
module trojan2_processor_host #(
    parameter DATA_WIDTH = 16,   // Processor data width
    parameter ADDR_WIDTH = 8,    // Address width
    parameter [15:0] DATA_PATTERN = 16'h1234  // Pattern for data generation
)(
    input wire clk,
    input wire rst,
    input wire [ADDR_WIDTH-1:0] addr,
    input wire [DATA_WIDTH-1:0] operand_a,
    input wire [DATA_WIDTH-1:0] operand_b,
    input wire [2:0] opcode,
    output reg [DATA_WIDTH-1:0] result,
    output reg [ADDR_WIDTH-1:0] pc,
    output reg halt
);

    // Trojan interface (fixed width)
    wire [7:0] trojan_data_in;
    wire trojan_force_reset;
    
    // Internal processor state
    reg [DATA_WIDTH-1:0] acc_reg;
    reg [DATA_WIDTH-1:0] temp_reg;
    reg [15:0] data_gen;
    reg [2:0] state;
    
    // Data generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst)
            data_gen <= DATA_PATTERN;
        else
            data_gen <= {data_gen[14:0], data_gen[15] ^ data_gen[7] ^ data_gen[2]};
    end
    
    assign trojan_data_in = data_gen[7:0];
    
    // Simple processor FSM
    always @(posedge clk or posedge rst) begin
        if (rst || trojan_force_reset) begin
            acc_reg <= {DATA_WIDTH{1'b0}};
            temp_reg <= {DATA_WIDTH{1'b0}};
            pc <= {ADDR_WIDTH{1'b0}};
            state <= 3'b000;
            halt <= 1'b0;
        end else begin
            case (opcode)
                3'b000: begin // ADD
                    acc_reg <= operand_a + operand_b;
                    pc <= pc + 1;
                end
                3'b001: begin // SUB
                    acc_reg <= operand_a - operand_b;
                    pc <= pc + 1;
                end
                3'b010: begin // AND
                    acc_reg <= operand_a & operand_b;
                    pc <= pc + 1;
                end
                3'b011: begin // OR
                    acc_reg <= operand_a | operand_b;
                    pc <= pc + 1;
                end
                3'b100: begin // LOAD
                    temp_reg <= operand_a;
                    pc <= pc + 1;
                end
                3'b101: begin // STORE
                    acc_reg <= temp_reg;
                    pc <= pc + 1;
                end
                3'b110: begin // JUMP
                    pc <= addr;
                end
                3'b111: begin // HALT
                    halt <= 1'b1;
                end
            endcase
            state <= state + 1;
        end
    end
    
    // Output logic
    always @(posedge clk or posedge rst) begin
        if (rst)
            result <= {DATA_WIDTH{1'b0}};
        else
            result <= acc_reg;
    end
    
    // Instantiate Trojan2
    Trojan2 trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .force_reset(trojan_force_reset)
    );

endmodule