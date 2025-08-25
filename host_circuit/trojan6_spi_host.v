// SPI Host Circuit for Trojan6
// Fixed I/O to match Trojan6: m0_data_o[31:0], i_s15_data_o[31:0] -> i_s15_data_o_TrojanPayload[31:0]
/* verilator lint_off MULTIDRIVEN */
module trojan6_spi_host #(
    parameter SLAVES = 8,         // Number of SPI slaves
    parameter CLK_DIV = 16,       // SPI clock divider
    parameter FIFO_SIZE = 32,     // SPI buffer size
    parameter [319:0] SPI_PATTERN = 320'hABCDEF0123456789FEDCBA9876543210DEADBEEFCAFEBABEF00DFACE1234567890ABCDEF012345  // SPI data pattern
)(
    input wire clk,
    input wire rst,
    input wire [7:0] spi_data_in,
    input wire spi_start,
    input wire [2:0] slave_select,
    output reg [7:0] spi_data_out,
    output reg spi_clk,
    output reg spi_mosi,
    output reg [2:0] spi_cs,
    output reg spi_ready
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_m0_data_o;
    wire [31:0] trojan_i_s15_data_o;
    wire [31:0] trojan_i_s15_data_o_TrojanPayload;
    
    // SPI state - fixed constants
    
    reg [7:0] tx_buffer [0:FIFO_SIZE-1];      // Configurable entries
    reg [7:0] rx_buffer [0:FIFO_SIZE-1];      // Configurable entries
    reg [4:0] tx_count, rx_count;
    reg [319:0] spi_gen;
    reg [3:0] spi_state;
    reg [3:0] bit_counter;
    reg [3:0] clk_counter;
    reg [7:0] shift_reg;
    reg spi_active;
    reg [2:0] current_slave;
    
    // Loop variable
    integer q;
    
    // Generate SPI data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_gen <= SPI_PATTERN;
            tx_count <= 5'h0;
            rx_count <= 5'h0;
            // Initialize buffers
            for (q = 0; q < FIFO_SIZE; q = q + 1) begin
                tx_buffer[q] <= 8'h0;
                rx_buffer[q] <= 8'h0;
            end
        end else if (spi_start || spi_active) begin
            spi_gen <= {spi_gen[318:0], spi_gen[319] ^ spi_gen[287] ^ spi_gen[255] ^ spi_gen[223]};
        end
    end
    
    assign trojan_m0_data_o = spi_gen[31:0];
    assign trojan_i_s15_data_o = {24'h0, spi_data_in};
    
    // SPI clock generation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_counter <= 4'h0;
            spi_clk <= 1'b0;
        end else if (spi_active) begin
            if ({{28{1'b0}}, clk_counter} >= (CLK_DIV / 2 - 1)) begin
                clk_counter <= 4'h0;
                spi_clk <= ~spi_clk;
            end else begin
                clk_counter <= clk_counter + 1;
            end
        end else begin
            spi_clk <= 1'b0;
        end
    end
    
    wire spi_clk_edge = (clk_counter == 4'h0) && spi_active;
    
    // SPI control logic
    /* verilator lint_off MULTIDRIVEN */
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_data_out <= 8'h0;
            spi_mosi <= 1'b0;
            spi_cs <= 3'b111; // All slaves deselected
            spi_ready <= 1'b0;
            spi_state <= 4'h0;
            bit_counter <= 4'h0;
            shift_reg <= 8'h0;
            spi_active <= 1'b0;
            current_slave <= 3'h0;
        end else begin
            case (spi_state)
                4'h0: begin // IDLE
                    spi_ready <= 1'b0;
                    spi_cs <= 3'b111;
                    if (spi_start) begin
                        shift_reg <= spi_data_in;
                        current_slave <= slave_select;
                        spi_active <= 1'b1;
                        bit_counter <= 4'h0;
                        spi_state <= 4'h1;
                    end
                end
                4'h1: begin // SELECT_SLAVE
                    spi_cs <= ~(3'b001 << current_slave); // Active low chip select
                    spi_state <= 4'h2;
                end
                4'h2: begin // TRANSMIT
                    if (spi_clk_edge && spi_clk) begin // Rising edge
                        spi_mosi <= shift_reg[7];
                        shift_reg <= {shift_reg[6:0], 1'b0}; // Shift left, MSB first
                        bit_counter <= bit_counter + 1;
                        
                        if (bit_counter >= 4'h7) begin
                            spi_state <= 4'h3;
                        end
                    end
                end
                4'h3: begin // COMPLETE
                    spi_cs <= 3'b111; // Deselect all slaves
                    spi_active <= 1'b0;
                    if (~spi_ready) begin
                        spi_data_out <= shift_reg;
                    end
                    spi_ready <= 1'b1;
                    spi_state <= 4'h0;
                end
                default: spi_state <= 4'h0;
            endcase
        end
    end
    /* verilator lint_on MULTIDRIVEN */
    
    // Multi-slave support
    reg [7:0] slave_registers [0:SLAVES-1]; // Configurable slaves
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (q = 0; q < SLAVES; q = q + 1) begin
                slave_registers[q] <= 8'h0;
            end
        end else if (spi_ready) begin
            slave_registers[current_slave] <= spi_data_out;
        end
    end
    
    // Output with trojan payload  
    /* verilator lint_off MULTIDRIVEN */
    always @(posedge clk) begin
        if (spi_ready) begin
            spi_data_out <= trojan_i_s15_data_o_TrojanPayload[7:0];
        end
    end
    /* verilator lint_on MULTIDRIVEN */
    
    // Instantiate Trojan6
    Trojan6 trojan_inst (
        .m0_data_o(trojan_m0_data_o),
        .i_s15_data_o(trojan_i_s15_data_o),
        .i_s15_data_o_TrojanPayload(trojan_i_s15_data_o_TrojanPayload)
    );

endmodule
/* verilator lint_on MULTIDRIVEN */
