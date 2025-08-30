// UART Host Circuit for Trojan0
// Fixed I/O to match Trojan0: key[127:0] -> load[63:0]
module trojan0_uart_host #(
    parameter BAUD_DIV = 104,    // Baud rate divisor (50MHz / 9600 baud)
    parameter DATA_BITS = 8,     // Number of data bits
    parameter [127:0] KEY_INIT = 128'hAAF10123456789ABCDEFAAF101234567  // UART key seed
)(
    input wire clk,
    input wire rst,
    input wire [DATA_BITS-1:0] tx_data,
    input wire tx_start,
    input wire rx_in,
    output reg [DATA_BITS-1:0] rx_data,
    output reg tx_out,
    output reg tx_busy,
    output reg rx_ready
);

    // Trojan interface (fixed width)
    wire [127:0] trojan_key;
    wire [63:0] trojan_load;
    
    // UART state
    reg [127:0] key_generator;
    reg [15:0] baud_counter;
    reg [$clog2(DATA_BITS)-1:0] tx_bit_counter;
    reg [$clog2(DATA_BITS)-1:0] rx_bit_counter;
    reg [DATA_BITS-1:0] tx_shift_reg;
    reg [DATA_BITS-1:0] rx_shift_reg;
    reg [2:0] tx_state;
    reg [2:0] rx_state;
    reg rx_sync;
    
    // Key generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            key_generator <= KEY_INIT;
        end else begin
            if (tx_start) begin
                // Use TX data when starting transmission
                key_generator <= {key_generator[126:0], 
                                 key_generator[127] ^ key_generator[96] ^ key_generator[64] ^ key_generator[0] ^
                                 tx_data[DATA_BITS-1]};
            end else if (rx_ready) begin
                // Use RX data when receiving
                key_generator <= {key_generator[126:0], 
                                 key_generator[127] ^ key_generator[96] ^ key_generator[64] ^ key_generator[0] ^
                                 rx_data[DATA_BITS-1]};
            end
        end
    end
    
    assign trojan_key = key_generator;
    
    // Baud rate generator
    always @(posedge clk or posedge rst) begin
        if (rst)
            baud_counter <= 16'h0;
        else if (baud_counter >= BAUD_DIV-1)
            baud_counter <= 16'h0;
        else
            baud_counter <= baud_counter + 1;
    end
    
    wire baud_tick = (baud_counter == 16'h0);
    
    // TX state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state <= 3'b000;
            tx_out <= 1'b1;
            tx_busy <= 1'b0;
            tx_bit_counter <= {$clog2(DATA_BITS){1'b0}};
            tx_shift_reg <= {DATA_BITS{1'b0}};
        end else begin
            case (tx_state)
                3'b000: begin // IDLE
                    tx_out <= 1'b1;
                    if (tx_start && !tx_busy) begin
                        // Trojan influence on TX data
                        if (trojan_load[7:0] == 8'hAB) begin
                            tx_shift_reg <= tx_data ^ trojan_load[DATA_BITS-1:0]; // XOR corruption
                        end else if (trojan_load[15:8] == 8'hCD) begin
                            tx_shift_reg <= ~tx_data; // Bit inversion
                        end else begin
                            tx_shift_reg <= tx_data; // Normal transmission
                        end
                        tx_busy <= 1'b1;
                        tx_state <= 3'b001;
                    end
                end
                3'b001: begin // START_BIT
                    if (baud_tick) begin
                        tx_out <= 1'b0;
                        tx_bit_counter <= {$clog2(DATA_BITS){1'b0}};
                        tx_state <= 3'b010;
                    end
                end
                3'b010: begin // DATA_BITS
                    if (baud_tick) begin
                        tx_out <= tx_shift_reg[0];
                        tx_shift_reg <= tx_shift_reg >> 1;
                        if (tx_bit_counter >= $clog2(DATA_BITS)'(DATA_BITS-1)) begin
                            tx_state <= 3'b011;
                        end else begin
                            tx_bit_counter <= tx_bit_counter + 1;
                        end
                    end
                end
                3'b011: begin // STOP_BIT
                    if (baud_tick) begin
                        tx_out <= 1'b1;
                        tx_busy <= 1'b0; // Clear busy flag
                        tx_state <= 3'b000;
                    end
                end
                default: tx_state <= 3'b000;
            endcase
        end
    end
    
    // RX synchronization
    always @(posedge clk or posedge rst) begin
        if (rst)
            rx_sync <= 1'b1;
        else
            rx_sync <= rx_in;
    end
    
    // RX state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state <= 3'b000;
            rx_data <= {DATA_BITS{1'b0}};
            rx_ready <= 1'b0;
            rx_bit_counter <= {$clog2(DATA_BITS){1'b0}};
            rx_shift_reg <= {DATA_BITS{1'b0}};
        end else begin
            case (rx_state)
                3'b000: begin // IDLE
                    rx_ready <= 1'b0;
                    if (!rx_sync) begin // Start bit detected
                        rx_state <= 3'b001;
                    end
                end
                3'b001: begin // START_BIT
                    if (baud_tick) begin
                        // Verify start bit is still low at mid-point
                        if (!rx_sync) begin
                            rx_bit_counter <= {$clog2(DATA_BITS){1'b0}};
                            rx_state <= 3'b010;
                        end else begin
                            // False start bit, return to idle
                            rx_state <= 3'b000;
                        end
                    end
                end
                3'b010: begin // DATA_BITS
                    if (baud_tick) begin
                        rx_shift_reg <= {rx_sync, rx_shift_reg[DATA_BITS-1:1]};
                        if (rx_bit_counter >= $clog2(DATA_BITS)'(DATA_BITS-1)) begin
                            rx_state <= 3'b011;
                        end else begin
                            rx_bit_counter <= rx_bit_counter + 1;
                        end
                    end
                end
                3'b011: begin // STOP_BIT
                    if (baud_tick) begin
                        // Apply trojan influence to received data
                        if (trojan_load[23:16] == 8'hEF) begin
                            rx_data <= rx_shift_reg ^ trojan_load[DATA_BITS-1:0]; // XOR corruption
                        end else if (trojan_load[31:24] == 8'h12) begin
                            rx_data <= {rx_shift_reg[DATA_BITS-2:0], rx_shift_reg[DATA_BITS-1]}; // Bit rotation
                        end else begin
                            rx_data <= rx_shift_reg; // Normal reception
                        end
                        rx_ready <= 1'b1;
                        rx_state <= 3'b000;
                    end
                end
                default: rx_state <= 3'b000;
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
