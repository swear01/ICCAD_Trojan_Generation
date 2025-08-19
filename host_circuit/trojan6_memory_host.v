// Memory Host Circuit for Trojan6
// Fixed I/O to match Trojan6: m0_data_o[31:0], i_s15_data_o[31:0] -> i_s15_data_o_TrojanPayload[31:0]
module trojan6_memory_host #(
    parameter MEM_SIZE = 64,     // Memory size (number of entries)
    parameter CACHE_SIZE = 8,    // Cache size
    parameter [95:0] MEM_PATTERN = 96'h123456789ABCDEF0FEDCBA98  // Pattern for memory data generation
)(
    input wire clk,
    input wire rst,
    input wire [31:0] mem_addr,
    input wire [31:0] write_data,
    input wire mem_read,
    input wire mem_write,
    output reg [31:0] read_data,
    output reg mem_ready
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_m0_data_o;
    wire [31:0] trojan_i_s15_data_o;
    wire [31:0] trojan_i_s15_data_o_TrojanPayload;
    
    // Memory state
    reg [31:0] memory [0:MEM_SIZE-1];
    reg [31:0] cache [0:CACHE_SIZE-1];
    reg [95:0] mem_gen;
    reg [2:0] mem_state;
    
    // Loop variable
    integer j;
    
    // Generate memory data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_gen <= MEM_PATTERN;
            // Initialize memory
            for (j = 0; j < MEM_SIZE; j = j + 1) begin
                memory[j] <= MEM_PATTERN[31:0] + j;
            end
            // Initialize cache
            for (j = 0; j < CACHE_SIZE; j = j + 1) begin
                cache[j] <= 32'h0;
            end
        end else if (mem_read || mem_write) begin
            mem_gen <= {mem_gen[93:0], mem_gen[95] ^ mem_gen[63] ^ mem_gen[31]};
        end
    end
    
    assign trojan_m0_data_o = mem_gen[31:0];
    assign trojan_i_s15_data_o = write_data;
    
    // Memory controller logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            read_data <= 32'h0;
            mem_ready <= 1'b0;
            mem_state <= 3'b000;
        end else begin
            case (mem_state)
                3'b000: begin // IDLE
                    mem_ready <= 1'b0;
                    if (mem_read || mem_write) begin
                        mem_state <= 3'b001;
                    end
                end
                3'b001: begin // ADDRESS_DECODE
                    mem_state <= 3'b010;
                end
                3'b010: begin // MEMORY_ACCESS
                    if (mem_write) begin
                        // Write trojan payload to memory
                        memory[mem_addr[$clog2(MEM_SIZE)-1:0]] <= trojan_i_s15_data_o_TrojanPayload;
                    end else if (mem_read) begin
                        // Read from memory
                        read_data <= memory[mem_addr[$clog2(MEM_SIZE)-1:0]];
                    end
                    mem_state <= 3'b011;
                end
                3'b011: begin // COMPLETE
                    mem_ready <= 1'b1;
                    mem_state <= 3'b000;
                end
                default: mem_state <= 3'b000;
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