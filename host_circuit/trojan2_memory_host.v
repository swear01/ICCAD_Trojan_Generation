// Memory Host Circuit for Trojan2
// Fixed I/O to match Trojan2: clk, rst, data_in[7:0] -> force_reset
module trojan2_memory_host #(
    parameter DATA_WIDTH = 16,    // Memory data width
    parameter ADDR_WIDTH = 4,     // Memory address width (16 locations)
    parameter [31:0] MEM_PATTERN = 32'hDEADBEEF  // Pattern for data generation
)(
    input wire clk,
    input wire rst,
    input wire [ADDR_WIDTH-1:0] address,
    input wire [DATA_WIDTH-1:0] write_data,
    input wire write_enable,
    input wire read_enable,
    output reg [DATA_WIDTH-1:0] read_data,
    output reg read_valid,
    output reg write_ack,
    output reg memory_error
);

    // Trojan interface (fixed width)
    wire [7:0] trojan_data_in;
    wire trojan_force_reset;
    
    // Memory array
    reg [DATA_WIDTH-1:0] memory [0:(1<<ADDR_WIDTH)-1];
    reg [31:0] data_pattern;
    reg [2:0] mem_state;
    reg [4:0] pattern_shift_count;
    
    // Data generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_pattern <= MEM_PATTERN;
            pattern_shift_count <= 5'b0;
        end else if (write_enable || read_enable) begin
            data_pattern <= {data_pattern[30:0], data_pattern[31] ^ data_pattern[21] ^ data_pattern[1] ^ data_pattern[0]};
            pattern_shift_count <= pattern_shift_count + 1;
        end
    end
    
    assign trojan_data_in = data_pattern[7:0];
    
    // Memory control state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_state <= 3'b000;
            read_valid <= 1'b0;
            write_ack <= 1'b0;
            memory_error <= 1'b0;
        end else if (trojan_force_reset) begin
            // Synchronous reset from trojan
            mem_state <= 3'b000;
            read_valid <= 1'b0;
            write_ack <= 1'b0;
            memory_error <= 1'b0;
        end else begin
            case (mem_state)
                3'b000: begin // IDLE
                    read_valid <= 1'b0;
                    write_ack <= 1'b0;
                    memory_error <= 1'b0;
                    if (write_enable) begin
                        mem_state <= 3'b001;
                    end else if (read_enable) begin
                        mem_state <= 3'b010;
                    end
                end
                3'b001: begin // WRITE
                    if (address < (1<<ADDR_WIDTH)) begin
                        memory[address] <= write_data;
                        write_ack <= 1'b1;
                    end else begin
                        memory_error <= 1'b1;
                    end
                    mem_state <= 3'b000;
                end
                3'b010: begin // READ
                    if (address < (1<<ADDR_WIDTH)) begin
                        read_data <= memory[address];
                        read_valid <= 1'b1;
                    end else begin
                        memory_error <= 1'b1;
                        read_data <= {DATA_WIDTH{1'b0}};
                    end
                    mem_state <= 3'b000;
                end
                default: mem_state <= 3'b000;
            endcase
        end
    end
    
    // Initialize memory
    integer i;
    always @(posedge rst or posedge trojan_force_reset) begin
        if (rst || trojan_force_reset) begin
            for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
                memory[i] <= {DATA_WIDTH{1'b0}};
            end
        end
    end
    
    // Instantiate Trojan2
    Trojan2 trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .force_reset(trojan_force_reset)
    );

endmodule

