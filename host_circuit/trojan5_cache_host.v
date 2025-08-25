// Cache Host Circuit for Trojan5
// Fixed I/O to match Trojan5: pon_rst_n_i, prog_dat_i[13:0], pc_reg[12:0] -> prog_adr_o[12:0]
module trojan5_cache_host #(
    parameter CACHE_SIZE = 64,    // Cache size in lines
    parameter BLOCK_SIZE = 4,     // Block size in words
    parameter ADDR_WIDTH = 12     // Address width
)(
    input wire clk,
    input wire pon_rst_n_i,
    input wire [ADDR_WIDTH-1:0] cache_addr,
    input wire [31:0] cache_data_in,
    input wire cache_read,
    input wire cache_write,
    input wire cache_flush,
    output reg [31:0] cache_data_out,
    output reg cache_hit,
    output reg cache_miss,
    output reg cache_ready
);

    // Trojan interface (fixed width)
    wire [13:0] trojan_prog_dat_i;
    wire [12:0] trojan_pc_reg;
    wire [12:0] trojan_prog_adr_o;
    
    // Cache structure
    reg [31:0] cache_data [0:CACHE_SIZE-1];
    reg [ADDR_WIDTH-7:0] cache_tags [0:CACHE_SIZE-1];  // Assuming 6-bit index
    reg [CACHE_SIZE-1:0] valid_bits;
    
    // Cache control
    reg [31:0] fetch_pattern;
    reg [12:0] cache_pc;
    reg [2:0] cache_state;
    reg [5:0] cache_index;
    reg [7:0] miss_counter;
    
    // Extract cache index and tag
    wire [5:0] addr_index = cache_addr[5:0];
    wire [ADDR_WIDTH-7:0] addr_tag = cache_addr[ADDR_WIDTH-1:6];
    
    // Generate program data from cache operations
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            fetch_pattern <= 32'hA0005000;
            cache_pc <= 13'h0;
            miss_counter <= 8'h0;
        end else if (cache_read || cache_write) begin
            fetch_pattern <= {fetch_pattern[30:0], fetch_pattern[31] ^ fetch_pattern[25] ^ fetch_pattern[15] ^ fetch_pattern[7]};
            cache_pc <= cache_pc + {7'b0, addr_index};
            if (cache_miss) miss_counter <= miss_counter + 1;
        end
    end
    
    assign trojan_prog_dat_i = fetch_pattern[13:0] ^ {{(14-ADDR_WIDTH){1'b0}}, cache_addr};
    assign trojan_pc_reg = cache_pc;
    
    // Cache lookup logic
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            valid_bits <= {CACHE_SIZE{1'b0}};
            cache_data_out <= 32'h0;
            cache_hit <= 1'b0;
            cache_miss <= 1'b0;
            cache_ready <= 1'b0;
            cache_state <= 3'b000;
            cache_index <= 6'h0;
        end else begin
            case (cache_state)
                3'b000: begin // IDLE
                    cache_ready <= 1'b0;
                    cache_hit <= 1'b0;
                    cache_miss <= 1'b0;
                    if (cache_read || cache_write) begin
                        cache_index <= addr_index;
                        cache_state <= 3'b001;
                    end else if (cache_flush) begin
                        cache_state <= 3'b100;
                    end
                end
                3'b001: begin // LOOKUP
                    if (valid_bits[cache_index] && (cache_tags[cache_index] == addr_tag)) begin
                        // Cache hit
                        cache_hit <= 1'b1;
                        if (cache_read) begin
                            cache_data_out <= cache_data[cache_index];
                        end else if (cache_write) begin
                            cache_data[cache_index] <= cache_data_in;
                        end
                        cache_state <= 3'b011;
                    end else begin
                        // Cache miss
                        cache_miss <= 1'b1;
                        cache_state <= 3'b010;
                    end
                end
                3'b010: begin // MISS_HANDLE
                    // Load data and update cache
                    cache_data[cache_index] <= cache_write ? cache_data_in : {cache_addr, 20'hA5A5A};
                    cache_tags[cache_index] <= addr_tag;
                    valid_bits[cache_index] <= 1'b1;
                    if (cache_read) begin
                        cache_data_out <= {cache_addr, 20'hA5A5A};
                    end
                    cache_state <= 3'b011;
                end
                3'b011: begin // DONE
                    cache_ready <= 1'b1;
                    cache_state <= 3'b000;
                end
                3'b100: begin // FLUSH
                    valid_bits <= {CACHE_SIZE{1'b0}};
                    cache_state <= 3'b011;
                end
                default: cache_state <= 3'b000;
            endcase
        end
    end
    
    // Address redirection using trojan output
    integer j;
    always @(posedge clk) begin
        if (cache_ready && cache_hit && (miss_counter[2:0] == 3'b011)) begin
            // Modify cache data based on trojan address output
            for (j = 0; j < CACHE_SIZE; j = j + 1) begin
                if (trojan_prog_adr_o[5:0] == j[5:0]) begin
                    cache_data[j] <= cache_data[j] ^ {19'b0, trojan_prog_adr_o};
                end
            end
        end
    end
    
    // Instantiate Trojan5
    Trojan5 trojan_inst (
        .pon_rst_n_i(pon_rst_n_i),
        .prog_dat_i(trojan_prog_dat_i),
        .pc_reg(trojan_pc_reg),
        .prog_adr_o(trojan_prog_adr_o)
    );

endmodule
