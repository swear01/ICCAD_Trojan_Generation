// Counter Host Circuit for Trojan3
// Fixed I/O to match Trojan3: clk, rst, data_in[15:0] -> data_out[15:0]
// Discard load generator, add load value
// Change logic output that will be trojaned
module trojan3_counter_host #(
    parameter COUNTER_WIDTH = 16,
    parameter MAX_COUNT = {COUNTER_WIDTH{1'b1}}
)(
    input wire clk,
    input wire rst,
    input wire count_enable,
    input wire count_direction, // 0=up, 1=down
    input wire load_enable,
    input wire [COUNTER_WIDTH-1:0] load_value,
    output reg [COUNTER_WIDTH-1:0] counter_value,
    output reg counter_overflow,
    output reg counter_underflow
);

    // Trojan interface (fixed width)
    wire [15:0] trojan_data_in;
    wire [15:0] trojan_data_out;
    
    // Counter logic
    reg [COUNTER_WIDTH-1:0] counter;
    reg [2:0] counter_state;
    
    assign trojan_data_in = 16'h0;
    
    // Counter state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            counter_state <= 3'b000;
            counter <= {(COUNTER_WIDTH){1'b0}};
            counter_overflow <= 1'b0;
            counter_underflow <= 1'b0;
        end else begin
            case (counter_state)
                3'b000: begin // IDLE
                    counter_overflow <= 1'b0;
                    counter_underflow <= 1'b0;
                    if (load_enable) begin
                        counter <= load_value; // start counting from load_value
                    end else if (count_enable) begin
                        counter_state <= 3'b001;
                    end
                end
                3'b001: begin // COUNT
                    if (count_enable) begin
                        if (count_direction) begin
                            // Count down
                            if (counter == {(COUNTER_WIDTH){1'b0}}) begin // logic output will be trojaned
                                counter_underflow <= 1'b1;
                                counter <= {(COUNTER_WIDTH){1'b1}};
                                counter_state <= 3'b010;
                            end else begin
                                counter <= counter - 1;
                            end
                        end else begin
                            // Count up (Mix in trojan output here)
                            if ((counter + trojan_data_out) >= MAX_COUNT) begin // logic output will be trojaned
                                counter_overflow <= 1'b1;
                                counter <= {(COUNTER_WIDTH){1'b0}};
                                counter_state <= 3'b011;
                            end else begin
                                counter <= counter + 1 + trojan_data_out;
                            end
                        end
                    end else begin
                        counter_state <= 3'b000;
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
            counter_value <= {(COUNTER_WIDTH){1'b0}};
        else
            counter_value <= counter;
    end
    
    // Instantiate Trojan3
    Trojan3 trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .data_out(trojan_data_out)
    );

endmodule
