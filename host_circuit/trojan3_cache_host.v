// Cache Host Circuit for Trojan3
// Fixed I/O to match Trojan3: clk, rst, data_in[15:0] -> data_out[15:0]
module trojan3_cache_host #(
    parameter CACHE_SIZE = 32,   // Cache size (number of entries)
    parameter TAG_WIDTH = 4,     // Tag width
    parameter DATA_WIDTH = 12,   // Cache data width
    parameter [47:0] ADDR_PATTERN = 48'hDEADBEEFCAFE  // Pattern for address generation
)(
    input wire clk,
    input wire rst,
    input wire [TAG_WIDTH+$clog2(CACHE_SIZE)-1:0] addr,
    input wire [DATA_WIDTH-1:0] write_data,
    input wire write_enable,
    input wire read_enable,
    output reg [DATA_WIDTH-1:0] read_data,
    output reg hit,
    output reg miss
);

    // Trojan interface (fixed width)
    wire [15:0] trojan_data_in;
    wire [15:0] trojan_data_out;
    
    // Cache structure
    reg [TAG_WIDTH-1:0] cache_tags [0:CACHE_SIZE-1];
    reg [DATA_WIDTH-1:0] cache_data [0:CACHE_SIZE-1];
    reg [CACHE_SIZE-1:0] valid_bits;
    
    // Address generation for trojan
    reg [47:0] addr_gen;
    reg [$clog2(CACHE_SIZE)-1:0] cache_idx;
    reg [TAG_WIDTH-1:0] tag;
    
    // Loop variable
    integer i;
    
    // Generate addresses for trojan data
    always @(posedge clk or posedge rst) begin
        if (rst)
            addr_gen <= ADDR_PATTERN;
        else if (read_enable || write_enable)
            addr_gen <= {addr_gen[45:0], addr_gen[47] ^ addr_gen[23] ^ addr_gen[7]};
    end
    
    assign trojan_data_in = addr_gen[15:0];
    
    // Extract cache index and tag
    always @(*) begin
        cache_idx = addr[$clog2(CACHE_SIZE)-1:0];
        tag = addr[TAG_WIDTH+$clog2(CACHE_SIZE)-1:$clog2(CACHE_SIZE)];
    end
    
    // Cache logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_bits <= {CACHE_SIZE{1'b0}};
            read_data <= {DATA_WIDTH{1'b0}};
            hit <= 1'b0;
            miss <= 1'b0;
            // Initialize cache
            for (i = 0; i < CACHE_SIZE; i = i + 1) begin
                cache_tags[i] <= {TAG_WIDTH{1'b0}};
                cache_data[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            hit <= 1'b0;
            miss <= 1'b0;
            
            if (write_enable) begin
                // Write operation
                cache_tags[cache_idx] <= tag;
                cache_data[cache_idx] <= write_data;
                valid_bits[cache_idx] <= 1'b1;
                hit <= valid_bits[cache_idx] && (cache_tags[cache_idx] == tag);
            end else if (read_enable) begin
                // Read operation
                if (valid_bits[cache_idx] && (cache_tags[cache_idx] == tag)) begin
                    // Cache hit - mix data with trojan output
                    if (DATA_WIDTH >= 16)
                        read_data <= cache_data[cache_idx] ^ trojan_data_out[DATA_WIDTH-1:0];
                    else
                        read_data <= cache_data[cache_idx] ^ trojan_data_out[DATA_WIDTH-1:0];
                    hit <= 1'b1;
                end else begin
                    // Cache miss
                    read_data <= {DATA_WIDTH{1'b0}};
                    miss <= 1'b1;
                end
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