// Cache Host Circuit for Trojan6
// Fixed I/O to match Trojan6: m0_data_o[31:0], i_s15_data_o[31:0] -> i_s15_data_o_TrojanPayload[31:0]
/* verilator lint_off MULTIDRIVEN */
module trojan6_cache_host #(
    parameter CACHE_LINES = 32,   // Number of cache lines
    parameter TAG_WIDTH = 24,     // Tag bit width
    parameter INDEX_WIDTH = 5,    // Index bit width
    parameter [159:0] CACHE_PATTERN = 160'h123456789ABCDEF0FEDCBA9876543210DEADBEEF  // Cache data pattern
)(
    input wire clk,
    input wire rst,
    input wire [31:0] addr,
    input wire [31:0] write_data,
    input wire cache_read,
    input wire cache_write,
    input wire cache_flush,
    output reg [31:0] read_data,
    output reg cache_hit,
    output reg cache_ready
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_m0_data_o;
    wire [31:0] trojan_i_s15_data_o;
    wire [31:0] trojan_i_s15_data_o_TrojanPayload;
    
    // Cache state - fixed constants
    
    reg [31:0] cache_data [0:CACHE_LINES-1];    // Configurable cache lines
    reg [TAG_WIDTH-1:0] cache_tags [0:CACHE_LINES-1];    // Configurable tag width
    reg [CACHE_LINES-1:0] cache_valid;          // Valid bits for cache lines
    reg [159:0] cache_gen;
    reg [2:0] cache_state;
    reg [4:0] cache_index;
    reg [23:0] cache_tag;
    
    // Extract address fields
    wire [4:0] addr_index = addr[6:2];   // 5-bit index
    wire [23:0] addr_tag = addr[30:7];   // 24-bit tag
    
    // Loop variable
    integer k;
    
    // Generate cache data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cache_gen <= CACHE_PATTERN;
            cache_valid <= 32'h0;
            // Initialize cache
            for (k = 0; k < 32; k = k + 1) begin
                cache_data[k] <= 32'h0;
                cache_tags[k] <= 24'h0;
            end
        end else if (cache_read || cache_write) begin
            cache_gen <= {cache_gen[158:0], cache_gen[159] ^ cache_gen[127] ^ cache_gen[95] ^ cache_gen[63]};
        end
    end
    
    assign trojan_m0_data_o = cache_gen[31:0];
    assign trojan_i_s15_data_o = write_data;
    
    // Cache control logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            read_data <= 32'h0;
            cache_hit <= 1'b0;
            cache_ready <= 1'b0;
            cache_state <= 3'b000;
            cache_index <= 5'h0;
            cache_tag <= 24'h0;
        end else begin
            case (cache_state)
                3'b000: begin // IDLE
                    cache_ready <= 1'b0;
                    cache_hit <= 1'b0;
                    if (cache_flush) begin
                        cache_valid <= 32'h0;
                        cache_state <= 3'b100;
                    end else if (cache_read || cache_write) begin
                        cache_index <= addr_index;
                        cache_tag <= addr_tag;
                        cache_state <= 3'b001;
                    end
                end
                3'b001: begin // TAG_CHECK
                    if (cache_valid[cache_index] && (cache_tags[cache_index] == cache_tag)) begin
                        // Cache hit
                        cache_hit <= 1'b1;
                        if (cache_read) begin
                            read_data <= cache_data[cache_index];
                        end else if (cache_write) begin
                            cache_data[cache_index] <= write_data;
                        end
                        cache_state <= 3'b011;
                    end else begin
                        // Cache miss
                        cache_hit <= 1'b0;
                        cache_state <= 3'b010;
                    end
                end
                3'b010: begin // MISS_HANDLE
                    // Simulate memory fetch and cache fill
                    cache_data[cache_index] <= cache_write ? write_data : {{24{1'b0}}, addr_index, 3'b101};
                    cache_tags[cache_index] <= cache_tag;
                    cache_valid[cache_index] <= 1'b1;
                    if (cache_read) begin
                        read_data <= {{24{1'b0}}, addr_index, 3'b101};
                    end
                    cache_state <= 3'b011;
                end
                3'b011: begin // DONE
                    cache_ready <= 1'b1;
                    cache_state <= 3'b000;
                end
                3'b100: begin // FLUSH
                    cache_ready <= 1'b1;
                    cache_state <= 3'b000;
                end
                default: cache_state <= 3'b000;
            endcase
        end
    end
    
    // Output with trojan payload
    always @(posedge clk) begin
        if (cache_ready) begin
            read_data <= trojan_i_s15_data_o_TrojanPayload;
        end
    end
    
    // Instantiate Trojan6
    Trojan6 trojan_inst (
        .m0_data_o(trojan_m0_data_o),
        .i_s15_data_o(trojan_i_s15_data_o),
        .i_s15_data_o_TrojanPayload(trojan_i_s15_data_o_TrojanPayload)
    );

endmodule
/* verilator lint_on MULTIDRIVEN */
