// Cache Host Circuit for Trojan0
// Fixed I/O to match Trojan0: key[127:0] -> load[63:0]
module trojan0_cache_host #(
    parameter CACHE_SIZE = 8,    // Number of cache lines (reduced)
    parameter DATA_WIDTH = 16,   // Cache line data width (reduced)
    parameter TAG_WIDTH = 4,     // Cache tag width (reduced)
    parameter [127:0] KEY_INIT = 128'hCAFEBABEDEADBEEFCAFEBABEDEADBEEF  // Cache key seed
)(
    input wire clk,
    input wire rst,
    input wire [TAG_WIDTH-1:0] addr_tag,
    input wire [5:0] addr_index,
    input wire [DATA_WIDTH-1:0] write_data,
    input wire cache_read,
    input wire cache_write,
    output reg [DATA_WIDTH-1:0] read_data,
    output reg cache_hit,
    output reg cache_ready
);

    // Trojan interface (fixed width)
    wire [127:0] trojan_key;
    wire [63:0] trojan_load;
    
    // Cache structure
    reg [DATA_WIDTH-1:0] cache_data [0:CACHE_SIZE-1];
    reg [TAG_WIDTH-1:0] cache_tags [0:CACHE_SIZE-1];
    reg [CACHE_SIZE-1:0] valid_bits;
    reg [127:0] key_generator;
    reg [2:0] cache_state;
    reg [$clog2(CACHE_SIZE)-1:0] access_index;
    
    
    // Key generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst)
            key_generator <= KEY_INIT;
        else if (cache_read || cache_write)
            key_generator <= {key_generator[119:0], key_generator[127:120] ^ {2'b0, addr_index}};
    end
    
    assign trojan_key = key_generator;
    
    // Cache lookup logic
    always @(*) begin
        if (addr_index < CACHE_SIZE) begin
            cache_hit = valid_bits[addr_index[$clog2(CACHE_SIZE)-1:0]] && (cache_tags[addr_index[$clog2(CACHE_SIZE)-1:0]] == addr_tag);
        end else begin
            cache_hit = 1'b0;
        end
    end
    
    // Cache state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_bits <= {CACHE_SIZE{1'b0}};
            cache_state <= 3'b000;
            cache_ready <= 1'b0;
            read_data <= {DATA_WIDTH{1'b0}};
            access_index <= {$clog2(CACHE_SIZE){1'b0}};
            
            // Initialize cache
            for (integer i = 0; i < CACHE_SIZE; i = i + 1) begin
                cache_data[i] <= {DATA_WIDTH{1'b0}};
                cache_tags[i] <= {TAG_WIDTH{1'b0}};
            end
        end else begin
            case (cache_state)
                3'b000: begin // IDLE
                    cache_ready <= 1'b0;
                    if (cache_read || cache_write) begin
                        access_index <= addr_index[$clog2(CACHE_SIZE)-1:0];
                        cache_state <= 3'b001;
                    end
                end
                3'b001: begin // ACCESS
                    if (cache_write) begin
                        // Write operation
                        cache_data[access_index] <= write_data;
                        cache_tags[access_index] <= addr_tag;
                        valid_bits[access_index] <= 1'b1;
                        cache_state <= 3'b010;
                    end else if (cache_read) begin
                        // Read operation
                        if (cache_hit) begin
                            read_data <= cache_data[access_index] ^ trojan_load[DATA_WIDTH-1:0];
                        end else begin
                            read_data <= {DATA_WIDTH{1'b0}};
                        end
                        cache_state <= 3'b010;
                    end
                end
                3'b010: begin // COMPLETE
                    cache_ready <= 1'b1;
                    cache_state <= 3'b000;
                end
                default: cache_state <= 3'b000;
            endcase
        end
    end
    
    // Instantiate Trojan0
    Trojan0 trojan_inst (
        .clk(clk),
        .rst(rst),
        .key(trojan_key),
        .load(trojan_load)
    );

endmodule
