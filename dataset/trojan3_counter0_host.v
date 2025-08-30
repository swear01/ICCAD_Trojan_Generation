// Counter Host Circuit for Trojan3
// Fixed I/O to match Trojan3: clk, rst, data_in[15:0] -> data_out[15:0]
module trojan3_counter_host #(
)(
    input wire clk,
    input wire rst,
    input wire count_enable,
    input wire count_direction, // 0=up, 1=down
    input wire load_enable,
    output reg [COUNTER_WIDTH-1:0] counter_value,
    output reg counter_overflow,
    output reg counter_underflow
);

    // Sizing parameters (converted from parameter to localparam)
    localparam COUNTER_WIDTH = 16;
    localparam MAX_COUNT = {COUNTER_WIDTH{1'b1}};

    // Trojan interface (fixed width)
    wire [15:0] trojan_data_in;
    wire [15:0] trojan_data_out;
    
    // Counter logic
    reg [COUNTER_WIDTH-1:0] counter;
    reg [COUNTER_WIDTH-1:0] load_gen;
    reg [2:0] counter_state;
    
    // Load pattern generation for host
    localparam [COUNTER_WIDTH-1:0] LOAD_SEED = COUNTER_WIDTH'hFF42;

    always @(posedge clk or posedge rst) begin
        if (rst)
            load_gen <= LOAD_SEED;
        else
            load_gen <= {load_gen[COUNTER_WIDTH-2:0], load_gen[15] ^ load_gen[11] ^ load_gen[7] ^ load_gen[3]};
    end
    
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
                        counter <= load_gen; // start counting from load_gen
                    end else if (count_enable) begin
                        counter_state <= 3'b001;
                    end
                end
                3'b001: begin // COUNT
                    if (count_enable) begin
                        if (count_direction) begin
                            // Count down
                            if (counter == {(COUNTER_WIDTH){1'b0}}) begin
                                counter_underflow <= 1'b1;
                                counter <= {(COUNTER_WIDTH){1'b1}};
                                counter_state <= 3'b010;
                            end else begin
                                counter <= counter - 1;
                            end
                        end else begin
                            // Count up
                            if (counter == MAX_COUNT) begin
                                counter_overflow <= 1'b1;
                                counter <= {(COUNTER_WIDTH){1'b0}};
                                counter_state <= 3'b011;
                            end else begin
                                counter <= counter + 1;
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
            // Mix trojan output into counter value
            counter_value <= counter + trojan_data_out;
    end
    
    // Instantiate Trojan3
    Trojan3 trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .data_out(trojan_data_out)
    );

endmodule
