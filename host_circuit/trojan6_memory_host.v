// Memory Host Circuit for Trojan6
// Fixed I/O to match Trojan6: m0_data_o[31:0], i_s15_data_o[31:0] -> i_s15_data_o_TrojanPayload[31:0]
module trojan6_memory_host (
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
    
    // Memory state - fixed constants
    localparam MEM_SIZE = 64;
    localparam CACHE_SIZE = 8;
    localparam [95:0] MEM_PATTERN = 96'h123456789ABCDEF0FEDCBA98;
    
    reg [31:0] memory [0:63];        // Fixed size
    reg [31:0] cache [0:7];          // Fixed size
    reg [95:0] mem_gen;
    reg [2:0] mem_state;
    
    // Loop variable
    integer j;
    
    // Generate memory data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_gen <= MEM_PATTERN;
            // Initialize memory
            for (j = 0; j < 64; j = j + 1) begin
                memory[j] <= MEM_PATTERN[31:0] + j;
            end
            // Initialize cache
            for (j = 0; j < 8; j = j + 1) begin
                cache[j] <= 32'h0;
            end
        end else if (mem_read || mem_write) begin
            mem_gen <= {mem_gen[94:0], mem_gen[95] ^ mem_gen[63] ^ mem_gen[31]};
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
                        memory[mem_addr[5:0]] <= trojan_i_s15_data_o_TrojanPayload;  // $clog2(64) = 6
                    end else if (mem_read) begin
                        // Read from memory
                        read_data <= memory[mem_addr[5:0]];
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
