// UART Host Circuit for Trojan1
// Fixed I/O to match Trojan1: clk, rst, r1 -> trigger
module trojan1_uart_host #(
    parameter BAUD_DIV = 104,     // Baud rate divisor (50MHz / 9600 baud)
    parameter DATA_BITS = 8,      // Number of data bits
    parameter STOP_BITS = 1,      // Number of stop bits
    parameter [17:0] R1_SEED = 18'h2CAFE  // Seed for r1 generation
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
    wire trojan_r1;
    wire trojan_trigger;
    
    // UART state
    reg [17:0] r1_shift_reg;
    reg [15:0] baud_counter;
    reg [3:0] bit_counter;
    reg [DATA_BITS-1:0] tx_shift_reg;
    reg [DATA_BITS-1:0] rx_shift_reg;
    reg [2:0] tx_state;
    reg [2:0] rx_state;
    reg rx_sync;
    reg [1:0] r1_phase;
    
    // R1 signal generation using multi-phase shift register
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r1_shift_reg <= R1_SEED;
            r1_phase <= 2'b00;
        end else if (tx_start || rx_ready || tx_busy) begin
            r1_shift_reg <= {r1_shift_reg[16:0], r1_shift_reg[17] ^ r1_shift_reg[10] ^ r1_shift_reg[2]};
            r1_phase <= r1_phase + 1;
        end
    end
    
    // Phase-based r1 selection
    always @(*) begin
        case (r1_phase)
            2'b00: trojan_r1 = r1_shift_reg[0];
            2'b01: trojan_r1 = r1_shift_reg[6];
            2'b10: trojan_r1 = r1_shift_reg[12];
            2'b11: trojan_r1 = r1_shift_reg[17];
            default: trojan_r1 = 1'b0;
        endcase
    end
    
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
            bit_counter <= 4'h0;
            tx_shift_reg <= {DATA_BITS{1'b0}};
        end else begin
            case (tx_state)
                3'b000: begin // IDLE
                    tx_out <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        tx_shift_reg <= tx_data;
                        tx_busy <= 1'b1;
                        tx_state <= 3'b001;
                    end
                end
                3'b001: begin // START_BIT
                    if (baud_tick) begin
                        tx_out <= 1'b0;
                        bit_counter <= 4'h0;
                        tx_state <= 3'b010;
                    end
                end
                3'b010: begin // DATA_BITS
                    if (baud_tick) begin
                        // Mix transmitted bit with trojan trigger
                        tx_out <= tx_shift_reg[0] ^ (trojan_trigger && (bit_counter == 4'h3));
                        tx_shift_reg <= tx_shift_reg >> 1;
                        if (bit_counter >= DATA_BITS-1) begin
                            tx_state <= 3'b011;
                        end else begin
                            bit_counter <= bit_counter + 1;
                        end
                    end
                end
                3'b011: begin // STOP_BIT
                    if (baud_tick) begin
                        tx_out <= 1'b1;
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
            bit_counter <= 4'h0;
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
                        bit_counter <= 4'h0;
                        rx_state <= 3'b010;
                    end
                end
                3'b010: begin // DATA_BITS
                    if (baud_tick) begin
                        rx_shift_reg <= {rx_sync, rx_shift_reg[DATA_BITS-1:1]};
                        if (bit_counter >= DATA_BITS-1) begin
                            rx_state <= 3'b011;
                        end else begin
                            bit_counter <= bit_counter + 1;
                        end
                    end
                end
                3'b011: begin // STOP_BIT
                    if (baud_tick) begin
                        rx_data <= rx_shift_reg;
                        rx_ready <= 1'b1;
                        rx_state <= 3'b000;
                    end
                end
                default: rx_state <= 3'b000;
            endcase
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

