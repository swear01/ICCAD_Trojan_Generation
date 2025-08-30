// UART Host Circuit for Trojan2
// Fixed I/O to match Trojan2: clk, rst, data_in[7:0] -> force_reset
module trojan2_uart_host #(
    parameter BAUD_DIV = 100,    // Baud rate divisor (50MHz/9600 ≈ 5208, simplified to 104)
    parameter DATA_BITS = 8,     // Number of data bits
    parameter [31:0] TX_PATTERN = 32'h5A5A5A5A  // Pattern for transmission data generation
)(
    input wire clk,
    input wire rst,
    input wire [7:0] tx_data,
    input wire tx_start,
    input wire rx_in,
    output reg tx_out,
    output reg [7:0] rx_data,
    output reg tx_busy,
    output reg rx_valid
);

    // Trojan interface (fixed width)
    wire [7:0] trojan_data_in;
    wire trojan_force_reset;
    
    // UART transmitter state
    reg [3:0] tx_state;
    reg [$clog2(BAUD_DIV)-1:0] tx_baud_counter;
    reg [3:0] tx_bit_counter;
    reg [7:0] tx_shift_reg;
    
    // UART receiver state  
    reg [3:0] rx_state;
    reg [$clog2(BAUD_DIV)-1:0] rx_baud_counter;
    reg [3:0] rx_bit_counter;
    reg [7:0] rx_shift_reg;
    reg rx_sync;
    
    // Data pattern generator for trojan
    reg [31:0] pattern_gen;
    reg [5:0] pattern_counter;
    
    // Generate data pattern for trojan input - continuous generation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pattern_gen <= TX_PATTERN;
            pattern_counter <= 6'b0;
        end else begin
            // Continuous pattern generation for more trojan activity
            pattern_gen <= {pattern_gen[30:0], pattern_gen[31] ^ pattern_gen[15] ^ pattern_gen[7]};
            pattern_counter <= pattern_counter + 1;
        end
    end
    
    // Mix pattern with actual RX data for trojan input
    assign trojan_data_in = pattern_gen[7:0] ^ rx_data;
    
    // UART Transmitter
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state <= 4'h0;
            tx_baud_counter <= {$clog2(BAUD_DIV){1'b0}};
            tx_bit_counter <= 4'h0;
            tx_shift_reg <= 8'h00;
            tx_out <= 1'b1;
            tx_busy <= 1'b0;
        end else if (trojan_force_reset) begin
            // Synchronous reset from trojan
            tx_state <= 4'h0;
            tx_baud_counter <= {$clog2(BAUD_DIV){1'b0}};
            tx_bit_counter <= 4'h0;
            tx_shift_reg <= 8'h00;
            tx_out <= 1'b1;
            tx_busy <= 1'b0;
        end else begin
            case (tx_state)
                4'h0: begin // IDLE
                    tx_out <= 1'b1;
                    if (tx_start) begin
                        tx_shift_reg <= tx_data;
                        tx_state <= 4'h1;
                        tx_busy <= 1'b1;
                        tx_baud_counter <= {$clog2(BAUD_DIV){1'b0}};
                    end
                end
                4'h1: begin // START BIT
                    tx_out <= 1'b0;
                    if (tx_baud_counter >= BAUD_DIV-1) begin
                        tx_baud_counter <= {$clog2(BAUD_DIV){1'b0}};
                        tx_state <= 4'h2;
                        tx_bit_counter <= 4'h0;
                    end else begin
                        tx_baud_counter <= tx_baud_counter + 1;
                    end
                end
                4'h2: begin // DATA BITS
                    tx_out <= tx_shift_reg[0];
                    if (tx_baud_counter >= BAUD_DIV-1) begin
                        tx_baud_counter <= {$clog2(BAUD_DIV){1'b0}};
                        tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                        if (tx_bit_counter >= DATA_BITS-1) begin
                            tx_state <= 4'h3;
                        end else begin
                            tx_bit_counter <= tx_bit_counter + 1;
                        end
                    end else begin
                        tx_baud_counter <= tx_baud_counter + 1;
                    end
                end
                4'h3: begin // STOP BIT
                    tx_out <= 1'b1;
                    if (tx_baud_counter >= BAUD_DIV-1) begin
                        tx_state <= 4'h0;
                        tx_busy <= 1'b0;
                    end else begin
                        tx_baud_counter <= tx_baud_counter + 1;
                    end
                end
            endcase
        end
    end
    
    // Proper UART Receiver implementation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state <= 4'h0;
            rx_baud_counter <= {$clog2(BAUD_DIV){1'b0}};
            rx_bit_counter <= 4'h0;
            rx_shift_reg <= 8'h00;
            rx_data <= 8'h00;
            rx_valid <= 1'b0;
            rx_sync <= 1'b1;
        end else if (trojan_force_reset) begin
            // Synchronous reset from trojan
            rx_state <= 4'h0;
            rx_baud_counter <= {$clog2(BAUD_DIV){1'b0}};
            rx_bit_counter <= 4'h0;
            rx_shift_reg <= 8'h00;
            rx_data <= 8'h00;
            rx_valid <= 1'b0;
            rx_sync <= 1'b1;
        end else begin
            rx_sync <= rx_in;
            
            case (rx_state)
                4'h0: begin // IDLE - Wait for start bit
                    rx_valid <= 1'b0;
                    if (!rx_in && rx_sync) begin // Falling edge detected (start bit)
                        rx_state <= 4'h1;
                        rx_baud_counter <= {$clog2(BAUD_DIV){1'b0}};
                        rx_bit_counter <= 4'h0;
                    end
                end
                4'h1: begin // START BIT - Wait for middle of start bit
                    if (rx_baud_counter >= (BAUD_DIV/2)) begin
                        if (!rx_in) begin // Confirm start bit
                            rx_state <= 4'h2;
                            rx_baud_counter <= {$clog2(BAUD_DIV){1'b0}};
                        end else begin
                            rx_state <= 4'h0; // False start, return to idle
                        end
                    end else begin
                        rx_baud_counter <= rx_baud_counter + 1;
                    end
                end
                4'h2: begin // DATA BITS - Sample in middle of each bit
                    if (rx_baud_counter >= BAUD_DIV-1) begin
                        rx_baud_counter <= {$clog2(BAUD_DIV){1'b0}};
                        rx_shift_reg <= {rx_in, rx_shift_reg[7:1]}; // LSB first
                        if (rx_bit_counter >= DATA_BITS-1) begin
                            rx_state <= 4'h3;
                        end else begin
                            rx_bit_counter <= rx_bit_counter + 1;
                        end
                    end else begin
                        rx_baud_counter <= rx_baud_counter + 1;
                    end
                end
                4'h3: begin // STOP BIT - Verify stop bit and output data
                    if (rx_baud_counter >= BAUD_DIV-1) begin
                        if (rx_in) begin // Valid stop bit
                            rx_data <= rx_shift_reg;
                            rx_valid <= 1'b1;
                        end
                        rx_state <= 4'h0;
                    end else begin
                        rx_baud_counter <= rx_baud_counter + 1;
                    end
                end
                default: rx_state <= 4'h0;
            endcase
        end
    end
    
    // Instantiate Trojan2
    Trojan2 trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .force_reset(trojan_force_reset)
    );

endmodule
