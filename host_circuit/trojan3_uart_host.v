// UART Host Circuit for Trojan3
// Fixed I/O to match Trojan3: clk, rst, data_in[15:0] -> data_out[15:0]
module trojan3_uart_host #(
    parameter [31:0] BAUD_PATTERN = 32'hB0BAFACE
)(
    input wire clk,
    input wire rst,
    input wire [7:0] tx_data,
    input wire tx_start,
    input wire rx_in,
    output reg [7:0] rx_data,
    output reg tx_out,
    output reg tx_busy,
    output reg rx_valid
);

    // Trojan interface (fixed width)
    wire [15:0] trojan_data_in;
    wire [15:0] trojan_data_out;
    
    // UART structure - fixed constants
    localparam BAUD_DIV = 104;
    localparam DATA_BITS = 8;
    
    // UART state
    reg [31:0] baud_gen;
    reg [7:0] tx_shift_reg;
    reg [7:0] rx_shift_reg;
    reg [7:0] baud_counter;
    reg [3:0] tx_bit_counter;
    reg [3:0] rx_bit_counter;
    reg [2:0] tx_state;
    reg [2:0] rx_state;
    reg rx_sync;
    
    // Baud pattern generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst)
            baud_gen <= BAUD_PATTERN;
        else if (tx_start || tx_busy || rx_valid)
            baud_gen <= {baud_gen[30:0], baud_gen[31] ^ baud_gen[28] ^ baud_gen[19] ^ baud_gen[7]};
    end
    
    assign trojan_data_in = baud_gen[15:0];
    
    // Baud rate generator
    always @(posedge clk or posedge rst) begin
        if (rst)
            baud_counter <= 8'h00;
        else if (baud_counter >= BAUD_DIV-1)
            baud_counter <= 8'h00;
        else
            baud_counter <= baud_counter + 1;
    end
    
    wire baud_tick = (baud_counter == 8'h00);
    
    // TX state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state <= 3'b000;
            tx_out <= 1'b1;
            tx_busy <= 1'b0;
            tx_bit_counter <= 4'h0;
            tx_shift_reg <= 8'h00;
        end else begin
            case (tx_state)
                3'b000: begin // IDLE
                    tx_out <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        tx_shift_reg <= tx_data;
                        tx_state <= 3'b001;
                        tx_busy <= 1'b1;
                    end
                end
                3'b001: begin // START_BIT
                    if (baud_tick) begin
                        tx_out <= 1'b0;
                        tx_bit_counter <= 4'h0;
                        tx_state <= 3'b010;
                    end
                end
                3'b010: begin // DATA_BITS
                    if (baud_tick) begin
                        tx_out <= tx_shift_reg[0];
                        tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                        if (tx_bit_counter >= DATA_BITS-1) begin
                            tx_state <= 3'b011;
                        end else begin
                            tx_bit_counter <= tx_bit_counter + 1;
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
            rx_data <= 8'h00;
            rx_valid <= 1'b0;
            rx_bit_counter <= 4'h0;
            rx_shift_reg <= 8'h00;
        end else begin
            case (rx_state)
                3'b000: begin // IDLE
                    rx_valid <= 1'b0;
                    if (!rx_sync) begin // Start bit detected
                        rx_state <= 3'b001;
                    end
                end
                3'b001: begin // START_BIT
                    if (baud_tick) begin
                        rx_bit_counter <= 4'h0;
                        rx_state <= 3'b010;
                    end
                end
                3'b010: begin // DATA_BITS
                    if (baud_tick) begin
                        rx_shift_reg <= {rx_sync, rx_shift_reg[7:1]};
                        if (rx_bit_counter >= DATA_BITS-1) begin
                            rx_state <= 3'b011;
                        end else begin
                            rx_bit_counter <= rx_bit_counter + 1;
                        end
                    end
                end
                3'b011: begin // STOP_BIT
                    if (baud_tick) begin
                        // Mix received data with trojan output
                        rx_data <= rx_shift_reg ^ trojan_data_out[7:0];
                        rx_valid <= 1'b1;
                        rx_state <= 3'b000;
                    end
                end
                default: rx_state <= 3'b000;
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
