// FIFO Host Circuit for Trojan0
// Fixed I/O to match Trojan0: key[127:0] -> load[63:0]
module trojan0_fifo_host #(
    parameter DATA_WIDTH = 16,   // FIFO data width
    parameter ADDR_WIDTH = 4,    // log2(DEPTH)
    parameter [127:0] KEY_INIT = 128'hF1F00123456789ABCDEFF1F0F1F0F1F0  // FIFO key seed
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] write_data,
    input wire write_enable,
    input wire read_enable,
    output reg [DATA_WIDTH-1:0] read_data,
    output reg fifo_full,
    output reg fifo_empty,
    output reg fifo_overflow,
    output reg fifo_underflow
);

    // Trojan interface (fixed width)
    wire [127:0] trojan_key;
    wire [63:0] trojan_load;
    
    // FIFO structure
    localparam DEPTH = 1 << ADDR_WIDTH;  // Derived parameter: 2^ADDR_WIDTH
    reg [DATA_WIDTH-1:0] fifo_mem [0:DEPTH-1];
    reg [ADDR_WIDTH:0] write_ptr;  // Extra bit for full/empty detection
    reg [ADDR_WIDTH:0] read_ptr;   // Extra bit for full/empty detection
    reg [127:0] key_generator;
    
    // Key generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            key_generator <= KEY_INIT;
        end else if (write_enable || read_enable) begin
            // Only use write_data when actually writing
            if (write_enable) begin
                key_generator <= {key_generator[126:0], 
                                 key_generator[127] ^ key_generator[96] ^ key_generator[64] ^ key_generator[0] ^
                                 write_data[DATA_WIDTH-1]};
            end else begin
                // Pure LFSR feedback on read
                key_generator <= {key_generator[126:0], 
                                 key_generator[127] ^ key_generator[96] ^ key_generator[64] ^ key_generator[0]};
            end
        end
    end
    
    assign trojan_key = key_generator;
    
    // FIFO status flags using pointer comparison
    always @(*) begin
        fifo_empty = (write_ptr == read_ptr);
        fifo_full = (write_ptr[ADDR_WIDTH-1:0] == read_ptr[ADDR_WIDTH-1:0]) && 
                   (write_ptr[ADDR_WIDTH] != read_ptr[ADDR_WIDTH]);
    end
    
    
    // Write pointer management
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            write_ptr <= {ADDR_WIDTH+1{1'b0}};
        end else if (write_enable && !fifo_full) begin
            write_ptr <= write_ptr + 1;
        end
    end
    
    // Read pointer management
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            read_ptr <= {ADDR_WIDTH+1{1'b0}};
        end else if (read_enable && !fifo_empty) begin
            read_ptr <= read_ptr + 1;
        end
    end
    
    // FIFO write operation
    always @(posedge clk) begin
        if (write_enable && !fifo_full) begin
            fifo_mem[write_ptr[ADDR_WIDTH-1:0]] <= write_data;
        end
    end
    
    // FIFO read operation with trojan load integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            read_data <= {DATA_WIDTH{1'b0}};
        end else if (read_enable && !fifo_empty) begin
            // Mix read data with trojan load (safe width handling)
            read_data <= fifo_mem[read_ptr[ADDR_WIDTH-1:0]] ^ 
                        (DATA_WIDTH'(trojan_load) & {DATA_WIDTH{1'b1}});
        end
    end
    
    // Error flag management - latched until reset
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            fifo_overflow <= 1'b0;
            fifo_underflow <= 1'b0;
        end else begin
            // Latch overflow/underflow flags
            if (write_enable && fifo_full) begin
                fifo_overflow <= 1'b1;
            end
            if (read_enable && fifo_empty) begin
                fifo_underflow <= 1'b1;
            end
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
