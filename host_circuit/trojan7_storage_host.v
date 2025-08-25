// Storage Host Circuit for Trojan7
// Fixed I/O to match Trojan7: wb_addr_i[31:0], wb_data_i[31:0], s0_data_i[31:0] -> slv_sel[3:0]
module trojan7_storage_host #(
    parameter BLOCK_SIZE = 512,      // Storage block size in bytes
    parameter CACHE_WAYS = 4,        // Number of cache ways
    parameter [63:0] STORAGE_PATTERN = 64'hDEADBEEFCAFEBABE  // Storage data pattern
)(
    input wire clk,
    input wire rst,
    input wire [31:0] storage_addr,
    input wire [31:0] write_data,
    input wire storage_read,
    input wire storage_write,
    input wire [7:0] storage_cmd,
    output reg [31:0] read_data,
    output reg storage_busy,
    output reg storage_done
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_wb_addr_i;
    wire [31:0] trojan_wb_data_i;
    wire [31:0] trojan_s0_data_i;
    wire [3:0] trojan_slv_sel;
    
    // Storage state - fixed constants
    localparam MAX_BLOCKS = 256;
    localparam SECTOR_SIZE = 512;
    
    reg [31:0] storage_blocks [0:255];  // Fixed storage blocks
    reg [31:0] cache_data [0:15];       // Fixed cache size
    reg [7:0] cache_tags [0:15];        // Fixed cache tags
    reg [15:0] cache_valid;
    reg [63:0] storage_gen;
    reg [4:0] storage_state;
    reg [7:0] current_block;
    reg [3:0] cache_index;
    reg [31:0] access_counter;
    
    // Loop variable
    integer s;
    
    // Generate storage data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            storage_gen <= STORAGE_PATTERN;
            access_counter <= 32'h0;
            cache_valid <= 16'h0;
            // Initialize cache
            for (s = 0; s < 16; s = s + 1) begin
                cache_data[s] <= 32'h0;
                cache_tags[s] <= 8'h0;
            end
        end else begin
            if (storage_read || storage_write) begin
                storage_gen <= {storage_gen[62:0], storage_gen[63] ^ storage_gen[31] ^ storage_gen[15]};
                access_counter <= access_counter + 1;
            end
            // Initialize storage blocks on first cycle only
            if (access_counter == 32'h0) begin
                for (s = 0; s < 256; s = s + 1) begin
                    storage_blocks[s] = STORAGE_PATTERN[31:0] + s[31:0];  // Use blocking assignment
                end
            end
        end
    end
    
    assign trojan_wb_addr_i = storage_addr;
    assign trojan_wb_data_i = {storage_gen[31:0]};
    assign trojan_s0_data_i = write_data;
    
    // Storage processing logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            read_data <= 32'h0;
            storage_busy <= 1'b0;
            storage_done <= 1'b0;
            storage_state <= 5'h0;
            current_block <= 8'h0;
            cache_index <= 4'h0;
        end else begin
            case (storage_state)
                5'h0: begin // IDLE
                    storage_done <= 1'b0;
                    storage_busy <= 1'b0;
                    if (storage_read) begin
                        current_block <= storage_addr[15:8];
                        cache_index <= storage_addr[7:4];
                        storage_busy <= 1'b1;
                        storage_state <= 5'h1;
                    end else if (storage_write) begin
                        current_block <= storage_addr[15:8];
                        cache_index <= storage_addr[7:4];
                        storage_busy <= 1'b1;
                        storage_state <= 5'h3;
                    end
                end
                5'h1: begin // READ_CACHE_CHECK
                    if (cache_valid[cache_index] && 
                        cache_tags[cache_index] == current_block) begin
                        // Cache hit
                        read_data <= cache_data[cache_index];
                        storage_state <= 5'h5;
                    end else begin
                        // Cache miss
                        storage_state <= 5'h2;
                    end
                end
                5'h2: begin // READ_STORAGE
                    // Simulate storage read delay
                    read_data <= storage_blocks[current_block];
                    // Update cache
                    cache_data[cache_index] <= storage_blocks[current_block];
                    cache_tags[cache_index] <= current_block;
                    cache_valid[cache_index] <= 1'b1;
                    storage_state <= 5'h5;
                end
                5'h3: begin // WRITE_CACHE
                    // Write to cache
                    cache_data[cache_index] <= write_data;
                    cache_tags[cache_index] <= current_block;
                    cache_valid[cache_index] <= 1'b1;
                    storage_state <= 5'h4;
                end
                5'h4: begin // WRITE_STORAGE
                    // Write to storage
                    storage_blocks[current_block] <= write_data;
                    storage_state <= 5'h5;
                end
                5'h5: begin // COMPLETE
                    // Apply trojan payload to read data
                    if (storage_read) begin
                        read_data <= read_data ^ {28'h0, trojan_slv_sel};
                    end
                    storage_busy <= 1'b0;
                    storage_done <= 1'b1;
                    storage_state <= 5'h0;
                end
                default: storage_state <= 5'h0;
            endcase
        end
    end
    
    // Instantiate Trojan7
    Trojan7 trojan_inst (
        .wb_addr_i(trojan_wb_addr_i),
        .wb_data_i(trojan_wb_data_i),
        .s0_data_i(trojan_s0_data_i),
        .slv_sel(trojan_slv_sel)
    );

endmodule
