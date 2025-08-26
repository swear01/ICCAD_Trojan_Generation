// I/O Controller Host Circuit for Trojan8
// Interface: a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], sel[2:0] -> y[15:0]
module trojan8_io_host #(
    parameter IO_PORTS = 16,              // Number of I/O ports
    parameter FIFO_DEPTH = 32,            // FIFO buffer depth
    parameter [127:0] IO_PATTERN = 128'h0F1E2D3C4B5A69788796A5B4C3D2E1F0  // I/O data pattern
)(
    input wire clk,
    input wire rst,
    input wire [15:0] io_addr,
    input wire [31:0] io_wdata,
    input wire io_read,
    input wire io_write,
    input wire [15:0] gpio_in,
    output reg [31:0] io_rdata,
    output reg [15:0] gpio_out,
    output reg io_ready
);

    // Trojan interface
    wire [7:0] trojan_a;
    wire [7:0] trojan_b;
    wire [7:0] trojan_c;
    wire [7:0] trojan_d;
    wire [7:0] trojan_e;
    wire [2:0] trojan_sel;
    wire [15:0] trojan_y;
    
    // I/O controller components
    reg [31:0] io_registers [0:15];  // Fixed to 16 I/O registers
    reg [31:0] tx_fifo [0:31];       // Fixed to 32 FIFO entries
    reg [31:0] rx_fifo [0:31];       // Fixed to 32 FIFO entries
    reg [127:0] io_gen;
    reg [3:0] io_state;
    reg [4:0] tx_ptr, rx_ptr;
    reg [5:0] tx_count, rx_count;  // Make 6-bit to match FIFO_DEPTH comparison
    reg [15:0] gpio_reg;
    
    integer k;
    
    // I/O controller state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            io_gen <= IO_PATTERN;
            io_state <= 4'h0;
            tx_ptr <= 5'h0;
            rx_ptr <= 5'h0;
            tx_count <= 6'h0;
            rx_count <= 6'h0;
            gpio_reg <= 16'h0;
            io_rdata <= 32'h0;
            gpio_out <= 16'h0;
            io_ready <= 1'b0;
            
            for (k = 0; k < 16; k = k + 1) begin
                io_registers[k] <= IO_PATTERN[31:0] + k;
            end
            for (k = 0; k < 32; k = k + 1) begin
                tx_fifo[k] <= 32'h0;
                rx_fifo[k] <= 32'h0;
            end
        end else begin
            io_gen <= {io_gen[126:0], io_gen[127]};
            
            case (io_state)
                4'h0: begin // IDLE
                    io_ready <= 1'b0;
                    if (io_read || io_write) begin
                        io_state <= 4'h1;
                    end else begin
                        gpio_reg <= gpio_in ^ trojan_y;
                        gpio_out <= gpio_reg;
                    end
                end
                4'h1: begin // ADDRESS_DECODE
                    if (io_addr[15:12] == 4'h0) begin
                        io_state <= 4'h2; // Register access
                    end else if (io_addr[15:12] == 4'h1) begin
                        io_state <= 4'h3; // FIFO access
                    end else begin
                        io_state <= 4'h0;
                    end
                end
                4'h2: begin // REGISTER_ACCESS
                    if (io_write && {28'h0, io_addr[3:0]} < IO_PORTS) begin  // Extend to 32-bit
                        io_registers[io_addr[3:0]] <= io_wdata ^ {16'h0, trojan_y};
                    end else if (io_read && {28'h0, io_addr[3:0]} < IO_PORTS) begin  // Extend to 32-bit
                        io_rdata <= io_registers[io_addr[3:0]] ^ {16'h0, trojan_y};
                    end
                    io_ready <= 1'b1;
                    io_state <= 4'h0;
                end
                4'h3: begin // FIFO_ACCESS
                    if (io_write && tx_count < FIFO_DEPTH) begin
                        tx_fifo[tx_ptr] <= io_wdata;
                        tx_ptr <= (tx_ptr + 1) & 5'h1F;
                        tx_count <= tx_count + 1;
                        // Use tx_fifo data in state machine
                        io_rdata <= tx_fifo[tx_ptr] ^ {24'h0, trojan_y[7:0]};
                    end else if (io_read && rx_count > 0) begin
                        io_rdata <= rx_fifo[rx_ptr];
                        rx_ptr <= (rx_ptr + 1) & 5'h1F;
                        rx_count <= rx_count - 1;
                    end
                    io_ready <= 1'b1;
                    io_state <= 4'h0;
                end
                default: io_state <= 4'h0;
            endcase
        end
    end
    
    // Connect trojan inputs
    assign trojan_a = io_gen[7:0];
    assign trojan_b = io_addr[7:0];
    assign trojan_c = io_wdata[7:0];
    assign trojan_d = gpio_in[7:0];
    assign trojan_e = {2'b00, tx_count[5:0]};  // Take only lower 6 bits to fit in 8-bit
    assign trojan_sel = io_state[2:0];
    
    // Instantiate Trojan8
    Trojan8 #(
        .MASK_00FF(16'h0055),
        .MASK_0F(8'h03),
        .MASK_F0F0(16'h5A5A)
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
