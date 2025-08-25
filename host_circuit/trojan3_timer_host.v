// Timer Host Circuit for Trojan3
// Fixed I/O to match Trojan3: clk, rst, data_in[15:0] -> data_out[15:0]
module trojan3_timer_host #(
    parameter [31:0] TIMER_PATTERN = 32'hDEAD7E4E,
    parameter PRESCALER_MAX = 255
)(
    input wire clk,
    input wire rst,
    input wire [15:0] load_value,
    input wire timer_enable,
    input wire timer_reset,
    input wire [15:0] compare_value,
    output reg [15:0] timer_count,
    output reg timer_overflow,
    output reg timer_match,
    output reg timer_active
);

    // Trojan interface (fixed width)
    wire [15:0] trojan_data_in;
    wire [15:0] trojan_data_out;
    
    // Timer structure - fixed constants
    localparam TIMER_WIDTH = 16;
    localparam PRESCALER_WIDTH = 8;
    
    // Timer state
    reg [15:0] counter;
    reg [7:0] prescaler;
    reg [31:0] timer_gen;
    reg [2:0] timer_state;
    reg timer_en_sync;
    
    // Timer pattern generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst)
            timer_gen <= TIMER_PATTERN;
        else if (timer_enable || timer_active)
            timer_gen <= {timer_gen[30:0], timer_gen[31] ^ timer_gen[26] ^ timer_gen[13] ^ timer_gen[4]};
    end
    
    assign trojan_data_in = timer_gen[15:0];
    
    // Prescaler
    always @(posedge clk or posedge rst) begin
        if (rst)
            prescaler <= 8'h00;
        else if (timer_reset)
            prescaler <= 8'h00;
        else if (timer_active) begin
            if (prescaler >= PRESCALER_MAX)
                prescaler <= 8'h00;
            else
                prescaler <= prescaler + 1;
        end
    end
    
    wire timer_tick = timer_active && (prescaler == 8'h00);
    
    // Timer state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            timer_state <= 3'b000;
            counter <= 16'h0000;
            timer_active <= 1'b0;
            timer_overflow <= 1'b0;
            timer_match <= 1'b0;
            timer_en_sync <= 1'b0;
        end else begin
            timer_en_sync <= timer_enable;
            
            case (timer_state)
                3'b000: begin // IDLE
                    timer_overflow <= 1'b0;
                    timer_match <= 1'b0;
                    timer_active <= 1'b0;
                    if (timer_enable && !timer_en_sync) begin // Rising edge
                        counter <= load_value;
                        timer_state <= 3'b001;
                        timer_active <= 1'b1;
                    end else if (timer_reset) begin
                        counter <= 16'h0000;
                    end
                end
                3'b001: begin // RUNNING
                    if (timer_reset || !timer_enable) begin
                        timer_state <= 3'b000;
                    end else if (timer_tick) begin
                        if (counter >= 16'hFFFF) begin
                            // Overflow
                            counter <= 16'h0000;
                            timer_overflow <= 1'b1;
                            timer_state <= 3'b010;
                        end else begin
                            counter <= counter + 1;
                            // Check for compare match
                            if ((counter + 1) == compare_value) begin
                                timer_match <= 1'b1;
                                timer_state <= 3'b011;
                            end
                        end
                    end
                end
                3'b010: begin // OVERFLOW
                    timer_overflow <= 1'b0;
                    timer_state <= 3'b000;
                end
                3'b011: begin // MATCH
                    timer_match <= 1'b0;
                    timer_state <= 3'b001;
                end
                default: timer_state <= 3'b000;
            endcase
        end
    end
    
    // Output with trojan integration
    always @(posedge clk or posedge rst) begin
        if (rst)
            timer_count <= 16'h0000;
        else
            // Mix timer count with trojan output
            timer_count <= counter ^ trojan_data_out;
    end
    
    // Instantiate Trojan3
    Trojan3 trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .data_out(trojan_data_out)
    );

endmodule
