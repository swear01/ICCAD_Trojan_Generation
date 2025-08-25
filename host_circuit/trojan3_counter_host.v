// Counter Host Circuit for Trojan3
// Fixed I/O to match Trojan3: clk, rst, data_in[15:0] -> data_out[15:0]
module trojan3_counter_host #(
    parameter [31:0] COUNT_SEED = 32'hC0FFEE42
)(
    input wire clk,
    input wire rst,
    input wire count_enable,
    input wire count_direction, // 0=up, 1=down
    input wire [15:0] load_value,
    input wire load_enable,
    output reg [15:0] counter_value,
    output reg counter_overflow,
    output reg counter_underflow
);

    // Trojan interface (fixed width)
    wire [15:0] trojan_data_in;
    wire [15:0] trojan_data_out;
    
    // Counter structure - fixed constants
    localparam COUNTER_WIDTH = 16;
    localparam MAX_COUNT = 65535;
    
    // Counter logic
    reg [15:0] counter;
    reg [31:0] count_gen;
    reg [2:0] counter_state;
    
    // Count pattern generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst)
            count_gen <= COUNT_SEED;
        else if (count_enable)
            count_gen <= {count_gen[30:0], count_gen[31] ^ count_gen[29] ^ count_gen[15] ^ count_gen[8]};
    end
    
    assign trojan_data_in = count_gen[15:0];
    
    // Counter state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            counter_state <= 3'b000;
            counter <= 16'h0000;
            counter_overflow <= 1'b0;
            counter_underflow <= 1'b0;
        end else begin
            case (counter_state)
                3'b000: begin // IDLE
                    counter_overflow <= 1'b0;
                    counter_underflow <= 1'b0;
                    if (load_enable) begin
                        counter <= load_value;
                    end else if (count_enable) begin
                        counter_state <= 3'b001;
                    end
                end
                3'b001: begin // COUNT
                    if (count_direction) begin
                        // Count down
                        if (counter == 16'h0000) begin
                            counter_underflow <= 1'b1;
                            counter <= 16'hFFFF;
                            counter_state <= 3'b010;
                        end else begin
                            counter <= counter - 1;
                            counter_state <= 3'b000;
                        end
                    end else begin
                        // Count up
                        if (counter >= MAX_COUNT) begin
                            counter_overflow <= 1'b1;
                            counter <= 16'h0000;
                            counter_state <= 3'b011;
                        end else begin
                            counter <= counter + 1;
                            counter_state <= 3'b000;
                        end
                    end
                end
                3'b010: begin // UNDERFLOW
                    counter_underflow <= 1'b0;
                    counter_state <= 3'b000;
                end
                3'b011: begin // OVERFLOW
                    counter_overflow <= 1'b0;
                    counter_state <= 3'b000;
                end
                default: counter_state <= 3'b000;
            endcase
        end
    end
    
    // Output with trojan integration
    always @(posedge clk or posedge rst) begin
        if (rst)
            counter_value <= 16'h0000;
        else
            // Mix counter value with trojan output
            counter_value <= counter ^ trojan_data_out;
    end
    
    // Instantiate Trojan3
    Trojan3 trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .data_out(trojan_data_out)
    );

endmodule
