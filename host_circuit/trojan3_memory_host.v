// Memory Host Circuit for Trojan3
// Fixed I/O to match Trojan3: clk, rst, data_in[15:0] -> data_out[15:0]
module trojan3_memory_host #(
    parameter [31:0] ADDR_SEED = 32'hFEEDFACE,
    parameter MEM_SIZE = 256
)(
    input wire clk,
    input wire rst,
    input wire [7:0] address,
    input wire [15:0] write_data,
    input wire write_enable,
    input wire read_enable,
    output reg [15:0] read_data,
    output reg read_valid,
    output reg write_ack
);

    // Trojan interface (fixed width)
    wire [15:0] trojan_data_in;
    wire [15:0] trojan_data_out;
    
    // Memory structure - fixed constants
    localparam ADDR_WIDTH = 8;
    
    // Memory array
    reg [15:0] memory [0:MEM_SIZE-1];
    
    // Address generation for trojan
    reg [31:0] addr_gen;
    reg [2:0] mem_state;
    
    // Generate addresses for trojan data
    always @(posedge clk or posedge rst) begin
        if (rst)
            addr_gen <= ADDR_SEED;
        else if (write_enable || read_enable)
            addr_gen <= {addr_gen[30:0], addr_gen[31] ^ addr_gen[27] ^ addr_gen[21] ^ addr_gen[3]};
    end
    
    assign trojan_data_in = addr_gen[15:0];
    
    // Memory control state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_state <= 3'b000;
            read_valid <= 1'b0;
            write_ack <= 1'b0;
        end else begin
            case (mem_state)
                3'b000: begin // IDLE
                    read_valid <= 1'b0;
                    write_ack <= 1'b0;
                    if (write_enable) begin
                        mem_state <= 3'b001;
                    end else if (read_enable) begin
                        mem_state <= 3'b010;
                    end
                end
                3'b001: begin // WRITE
                    memory[address] <= write_data;
                    write_ack <= 1'b1;
                    mem_state <= 3'b000;
                end
                3'b010: begin // READ
                    // Mix read data with trojan output
                    read_data <= memory[address] ^ trojan_data_out;
                    read_valid <= 1'b1;
                    mem_state <= 3'b000;
                end
                default: mem_state <= 3'b000;
            endcase
        end
    end
    
    // Initialize memory
    integer i;
    always @(posedge rst) begin
        if (rst) begin
            for (i = 0; i < MEM_SIZE; i = i + 1) begin
                memory[i] <= 16'h0000;
            end
        end
    end
    
    // Instantiate Trojan3
    Trojan3 trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .data_out(trojan_data_out)
    );

endmodule
