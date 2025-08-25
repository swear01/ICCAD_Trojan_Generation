// UART Host Circuit for Trojan6
// Fixed I/O to match Trojan6: m0_data_o[31:0], i_s15_data_o[31:0] -> i_s15_data_o_TrojanPayload[31:0]
/* verilator lint_off MULTIDRIVEN */
module trojan6_uart_host #(
    parameter BAUD_DIV = 5208,        // Baud rate divider (CLK_FREQ/BAUD_RATE)
    parameter FIFO_DEPTH = 16,        // FIFO depth
    parameter [287:0] UART_PATTERN = 288'hDEADBEEFCAFEBABEF00DFACEFEEDFACE0123456789ABCDEF0123456789ABCDEF012345  // UART data pattern
)(
    input wire clk,
    input wire rst,
    input wire [7:0] tx_data,
    input wire tx_start,
    input wire rx_in,
    output reg [7:0] rx_data,
    output reg tx_out,
    output reg tx_busy,
    output reg rx_ready
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_m0_data_o;
    wire [31:0] trojan_i_s15_data_o;
    wire [31:0] trojan_i_s15_data_o_TrojanPayload;
    
    // UART state - fixed constants
    
    reg [7:0] tx_fifo [0:FIFO_DEPTH-1];        // Configurable FIFO entries
    reg [7:0] rx_fifo [0:FIFO_DEPTH-1];        // Configurable FIFO entries
    reg [3:0] tx_head, tx_tail;
    reg [3:0] rx_head, rx_tail;
    reg [287:0] uart_gen;
    reg [3:0] uart_state;
    reg [31:0] baud_counter;
    reg [3:0] bit_counter;
    reg [7:0] tx_shift_reg;
    reg [7:0] rx_shift_reg;
    reg tx_active, rx_active;
    
    // Loop variable
    integer p;
    
    // Generate UART data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            uart_gen <= UART_PATTERN;
            tx_head <= 4'h0;
            tx_tail <= 4'h0;
            rx_head <= 4'h0;
            rx_tail <= 4'h0;
            // Initialize FIFOs
            for (p = 0; p < FIFO_DEPTH; p = p + 1) begin
                tx_fifo[p] <= 8'h0;
                rx_fifo[p] <= 8'h0;
            end
        end else if (tx_start || rx_ready) begin
            uart_gen <= {uart_gen[286:0], uart_gen[287] ^ uart_gen[255] ^ uart_gen[223] ^ uart_gen[191]};
        end
    end
    
    assign trojan_m0_data_o = uart_gen[31:0];
    assign trojan_i_s15_data_o = {24'h0, tx_data};
    
    // Baud rate generator
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_counter <= 32'h0;
        end else begin
            if (baud_counter >= (BAUD_DIV - 1)) begin
                baud_counter <= 32'h0;
            end else begin
                baud_counter <= baud_counter + 1;
            end
        end
    end
    
    wire baud_tick = (baud_counter == 32'h0);
    
    // UART transmitter
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_out <= 1'b1;
            tx_busy <= 1'b0;
            tx_shift_reg <= 8'h0;
            bit_counter <= 4'h0;
            tx_active <= 1'b0;
        end else begin
            if (!tx_active) begin
                if (tx_start && !tx_busy) begin
                    // Load data into shift register
                    tx_shift_reg <= tx_data;
                    tx_busy <= 1'b1;
                    tx_active <= 1'b1;
                    bit_counter <= 4'h0;
                end else begin
                    tx_out <= 1'b1; // Idle high
                end
            end else if (baud_tick) begin
                case (bit_counter)
                    4'h0: begin // Start bit
                        tx_out <= 1'b0;
                        bit_counter <= bit_counter + 1;
                    end
                    4'h1, 4'h2, 4'h3, 4'h4, 4'h5, 4'h6, 4'h7, 4'h8: begin // Data bits
                        tx_out <= tx_shift_reg[bit_counter - 1];
                        bit_counter <= bit_counter + 1;
                    end
                    4'h9: begin // Stop bit
                        tx_out <= 1'b1;
                        bit_counter <= bit_counter + 1;
                    end
                    4'hA: begin // Complete
                        tx_busy <= 1'b0;
                        tx_active <= 1'b0;
                        bit_counter <= 4'h0;
                    end
                    default: begin
                        tx_busy <= 1'b0;
                        tx_active <= 1'b0;
                        bit_counter <= 4'h0;
                    end
                endcase
            end
        end
    end
    
    // UART receiver
    reg [1:0] rx_sync;
    wire rx_negedge = (rx_sync == 2'b10);
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_sync <= 2'b11;
        end else begin
            rx_sync <= {rx_sync[0], rx_in};
        end
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_data <= 8'h0;
            rx_ready <= 1'b0;
            rx_shift_reg <= 8'h0;
            rx_active <= 1'b0;
        end else begin
            rx_ready <= 1'b0;
            
            if (!rx_active) begin
                if (rx_negedge) begin // Start bit detected
                    rx_active <= 1'b1;
                    bit_counter <= 4'h0;
                end
            end else if (baud_tick) begin
                if (bit_counter < 4'h8) begin // Data bits
                    rx_shift_reg <= {rx_in, rx_shift_reg[7:1]};
                    bit_counter <= bit_counter + 1;
                end else if (bit_counter == 4'h8) begin // Stop bit
                    if (rx_in == 1'b1) begin // Valid stop bit
                        rx_data <= rx_shift_reg;
                        rx_ready <= 1'b1;
                    end
                    rx_active <= 1'b0;
                    bit_counter <= 4'h0;
                end
            end
        end
    end
    
    // Output with trojan payload
    always @(posedge clk) begin
        if (rx_ready) begin
            rx_data <= trojan_i_s15_data_o_TrojanPayload[7:0];
        end
    end
    
    // Instantiate Trojan6
    Trojan6 trojan_inst (
        .m0_data_o(trojan_m0_data_o),
        .i_s15_data_o(trojan_i_s15_data_o),
        .i_s15_data_o_TrojanPayload(trojan_i_s15_data_o_TrojanPayload)
    );

endmodule
/* verilator lint_on MULTIDRIVEN */
