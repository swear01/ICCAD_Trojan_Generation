// Cache Host Circuit for Trojan3
// Fixed I/O to match Trojan3: clk, rst, data_in[15:0] -> data_out[15:0]
module trojan3_cache_host (
    input wire clk,
    input wire rst,
    input wire [8:0] addr,           // Fixed width: 4 + 5 bits
    input wire [11:0] write_data,    // Fixed width
    input wire write_enable,
    input wire read_enable,
    output reg [11:0] read_data,     // Fixed width
    output reg hit,
    output reg miss
);

    // Trojan interface (fixed width)
    wire [15:0] trojan_data_in;
    wire [15:0] trojan_data_out;
    
    // Cache structure - fixed constants
    localparam CACHE_SIZE = 32;
    localparam TAG_WIDTH = 4;
    localparam [47:0] ADDR_PATTERN = 48'hDEADBEEFCAFE;
    
    reg [3:0] cache_tags [0:31];     // Fixed size
    reg [11:0] cache_data [0:31];    // Fixed size
    reg [31:0] valid_bits;           // Fixed size
    
    // Address generation for trojan
    reg [47:0] addr_gen;
    reg [4:0] cache_idx;             // Fixed size: $clog2(32) = 5
    reg [3:0] tag;                   // Fixed size
    
    // Loop variable
    integer i;
    
    // Generate addresses for trojan data
    always @(posedge clk or posedge rst) begin
        if (rst)
            addr_gen <= ADDR_PATTERN;
        else if (read_enable || write_enable)
            addr_gen <= {addr_gen[46:0], addr_gen[47] ^ addr_gen[23] ^ addr_gen[7]};
    end
    
    assign trojan_data_in = addr_gen[15:0];
    
    // Extract cache index and tag
    always @(*) begin
        cache_idx = addr[4:0];  // bits [4:0] for 32-entry cache
        tag = addr[8:5];        // bits [8:5] for 4-bit tag
    end
    
    // Cache logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_bits <= 32'h0;
            read_data <= 12'h0;
            hit <= 1'b0;
            miss <= 1'b0;
            // Initialize cache
            for (i = 0; i < 32; i = i + 1) begin
                cache_tags[i] <= 4'h0;
                cache_data[i] <= 12'h0;
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
                    read_data <= cache_data[cache_idx] ^ trojan_data_out[11:0];
                    hit <= 1'b1;
                end else begin
                    // Cache miss
                    read_data <= 12'h0;
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
