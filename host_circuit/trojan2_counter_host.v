// Counter Host Circuit for Trojan2
// Fixed I/O to match Trojan2: clk, rst, data_in[7:0] -> force_reset
module trojan2_counter_host #(
    parameter COUNTER_WIDTH = 12,  // Counter width
    parameter COUNT_MAX = 2048,    // Maximum count value
    parameter [27:0] COUNT_PATTERN = 28'hFEEDBEE  // Pattern for data generation
)(
    input wire clk,
    input wire rst,
    input wire count_enable,
    input wire count_direction,  // 0=up, 1=down
    input wire [COUNTER_WIDTH-1:0] load_value,
    input wire load_counter,
    output reg [COUNTER_WIDTH-1:0] counter_value,
    output reg counter_overflow,
    output reg counter_underflow,
    output reg counter_zero
);

    // Trojan interface (fixed width)
    reg [7:0] trojan_data_in;
    wire trojan_force_reset;
    
    // Counter logic
    reg [COUNTER_WIDTH-1:0] counter;
    reg [27:0] pattern_gen;
    reg [2:0] pattern_byte_sel;
    
    // Data generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pattern_gen <= COUNT_PATTERN;
            pattern_byte_sel <= 3'b0;
        end else if (count_enable) begin
            // Update pattern on every count operation for more trojan activity
            pattern_gen <= {pattern_gen[26:0], pattern_gen[27] ^ pattern_gen[22] ^ pattern_gen[16] ^ pattern_gen[3]};
            if (counter_overflow || counter_underflow || (counter % 16 == 0)) begin
                // Change pattern selection more frequently
                pattern_byte_sel <= pattern_byte_sel + 1;
            end
        end
    end
    
    // Select byte from pattern for trojan data
    always @(*) begin
        case (pattern_byte_sel[2:0])
            3'b000: trojan_data_in = pattern_gen[7:0];
            3'b001: trojan_data_in = pattern_gen[15:8];
            3'b010: trojan_data_in = pattern_gen[23:16];
            3'b011: trojan_data_in = pattern_gen[27:20];
            3'b100: trojan_data_in = pattern_gen[7:0] ^ pattern_gen[15:8];
            3'b101: trojan_data_in = pattern_gen[23:16] ^ pattern_gen[7:0];
            3'b110: trojan_data_in = pattern_gen[27:20] ^ pattern_gen[15:8];
            3'b111: trojan_data_in = pattern_gen[27:20] ^ pattern_gen[7:0];
            default: trojan_data_in = 8'h00;
        endcase
    end
    
    // Counter state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= {COUNTER_WIDTH{1'b0}};
            counter_overflow <= 1'b0;
            counter_underflow <= 1'b0;
            counter_zero <= 1'b1;
        end else if (trojan_force_reset) begin
            // Synchronous reset from trojan
            counter <= {COUNTER_WIDTH{1'b0}};
            counter_overflow <= 1'b0;
            counter_underflow <= 1'b0;
            counter_zero <= 1'b1;
        end else begin
            
            if (load_counter) begin
                counter <= load_value;
                counter_zero <= (load_value == {COUNTER_WIDTH{1'b0}});
                counter_overflow <= 1'b0;
                counter_underflow <= 1'b0;
            end else if (count_enable) begin
                if (count_direction) begin
                    // Count down
                    if (counter == {COUNTER_WIDTH{1'b0}}) begin
                        counter_underflow <= 1'b1;
                        counter <= COUNTER_WIDTH'(COUNT_MAX - 1);  // Wrap to COUNT_MAX-1, not all 1's
                        counter_zero <= 1'b0;
                    end else begin
                        counter <= counter - 1;
                        counter_zero <= (counter == {{(COUNTER_WIDTH-1){1'b0}}, 1'b1});  // Will be zero next cycle
                        counter_underflow <= 1'b0;
                    end
                end else begin
                    // Count up
                    if (counter == COUNTER_WIDTH'(COUNT_MAX - 1)) begin
                        counter_overflow <= 1'b1;
                        counter <= {COUNTER_WIDTH{1'b0}};
                        counter_zero <= 1'b1;  // Next state will be zero
                    end else begin
                        counter <= counter + 1;
                        counter_zero <= (counter == COUNTER_WIDTH'(COUNT_MAX - 2));  // Will overflow to zero next cycle
                        counter_overflow <= 1'b0;
                    end
                end
            end
        end
    end
    
    // Output counter value
    always @(posedge clk or posedge rst) begin
        if (rst)
            counter_value <= {COUNTER_WIDTH{1'b0}};
        else if (trojan_force_reset)
            counter_value <= {COUNTER_WIDTH{1'b0}};
        else
            counter_value <= counter;
    end
    
    // Instantiate Trojan2
    Trojan2 trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .force_reset(trojan_force_reset)
    );

endmodule

