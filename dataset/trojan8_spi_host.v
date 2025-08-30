// SPI Controller Host Circuit for Trojan8
// Interface: a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], sel[2:0] -> y[15:0]
module trojan8_spi_host #(
    parameter [71:0] SPI_PATTERN = 72'h23456789ABCDEF0123  // SPI data pattern
)(
    input wire clk,
    input wire rst,
    input wire [7:0] tx_data,
    input wire [1:0] slave_sel,
    input wire spi_start,
    input wire spi_cpol,
    input wire spi_cpha,
    input wire spi_miso,
    output reg spi_sclk,
    output reg spi_mosi,
    output reg [3:0] spi_ss_n,
    output reg [7:0] rx_data,
    output reg spi_ready
);

    // Sizing parameters (converted from parameter to localparam)
    localparam SPI_SLAVES = 4;             // Number of SPI slave selects
    localparam CLK_DIV = 8;                // SPI clock divisor

    // Trojan interface
    wire [7:0] trojan_a;
    wire [7:0] trojan_b;
    wire [7:0] trojan_c;
    wire [7:0] trojan_d;
    wire [7:0] trojan_e;
    wire [2:0] trojan_sel;
    wire [15:0] trojan_y;
    
    // SPI controller components
    reg [71:0] spi_gen;
    reg [2:0] spi_state;
    reg [7:0] tx_shift_reg;
    reg [7:0] rx_shift_reg;
    reg [3:0] bit_counter;
    reg [3:0] clk_counter;
    reg spi_clk_reg;
    reg [7:0] transaction_counter;
    
    // SPI controller state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_gen <= SPI_PATTERN;
            spi_state <= 3'h0;
            tx_shift_reg <= 8'h0;
            rx_shift_reg <= 8'h0;
            bit_counter <= 4'h0;
            clk_counter <= 4'h0;
            spi_clk_reg <= 1'b0;
            transaction_counter <= 8'h0;
            spi_sclk <= 1'b0;
            spi_mosi <= 1'b0;
            spi_ss_n <= 4'hF;
            rx_data <= 8'h0;
            spi_ready <= 1'b1;
        end else begin
            spi_gen <= {spi_gen[70:0], spi_gen[71]};
            
            case (spi_state)
                3'h0: begin // IDLE
                    spi_ready <= 1'b1;
                    spi_ss_n <= 4'hF;
                    spi_sclk <= spi_cpol;
                    if (spi_start && {30'h0, slave_sel} < SPI_SLAVES) begin  // Extend to 32-bit
                        tx_shift_reg <= tx_data ^ trojan_y[7:0];
                        rx_shift_reg <= 8'h0;
                        bit_counter <= 4'h8;
                        clk_counter <= 4'h0;
                        spi_clk_reg <= spi_cpol;
                        transaction_counter <= transaction_counter + 1;
                        spi_ready <= 1'b0;
                        spi_state <= 3'h1;
                    end
                end
                3'h1: begin // SETUP
                    spi_ss_n <= ~(4'h1 << slave_sel);
                    spi_state <= 3'h2;
                end
                3'h2: begin // TRANSFER
                    clk_counter <= clk_counter + 1;
                    if (clk_counter >= CLK_DIV) begin
                        clk_counter <= 4'h0;
                        spi_clk_reg <= ~spi_clk_reg;
                        
                        if (spi_clk_reg == spi_cpha) begin
                            // Setup phase
                            spi_mosi <= tx_shift_reg[7];
                        end else begin
                            // Sample phase
                            tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                            rx_shift_reg <= {rx_shift_reg[6:0], spi_miso};
                            bit_counter <= bit_counter - 1;
                            if (bit_counter == 1) begin
                                spi_state <= 3'h3;
                            end
                        end
                    end
                    spi_sclk <= spi_clk_reg;
                end
                3'h3: begin // COMPLETE
                    rx_data <= rx_shift_reg ^ trojan_y[7:0];
                    spi_sclk <= spi_cpol;
                    spi_state <= 3'h4;
                end
                3'h4: begin // CLEANUP
                    spi_ss_n <= 4'hF;
                    spi_state <= 3'h0;
                end
                default: spi_state <= 3'h0;
            endcase
        end
    end
    
    // Connect trojan inputs
    assign trojan_a = spi_gen[7:0];
    assign trojan_b = tx_data;
    assign trojan_c = rx_shift_reg;
    assign trojan_d = {6'b000000, slave_sel};
    assign trojan_e = transaction_counter;
    assign trojan_sel = spi_state;
    
    // Instantiate Trojan8
    Trojan8 #(
        .MASK_00FF(16'h0099),
        .MASK_0F(8'h0A),
        .MASK_F0F0(16'h9999)
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
