// PWM Host Circuit for Trojan2
// Fixed I/O to match Trojan2: clk, rst, data_in[7:0] -> force_reset
module trojan2_pwm_host #(
    parameter PWM_WIDTH = 12,     // PWM counter resolution
    parameter PWM_CHANNELS = 3,   // Number of PWM channels
    parameter [25:0] PWM_PATTERN = 26'h123ABCD  // Pattern for data generation
)(
    input wire clk,
    input wire rst,
    input wire [PWM_WIDTH-1:0] duty_cycle_ch0,
    input wire [PWM_WIDTH-1:0] duty_cycle_ch1,
    input wire [PWM_WIDTH-1:0] duty_cycle_ch2,
    input wire [PWM_WIDTH-1:0] period_value,
    input wire pwm_enable,
    output reg pwm_out_ch0,
    output reg pwm_out_ch1,
    output reg pwm_out_ch2,
    output reg period_complete
);

    // Trojan interface (fixed width)
    wire [7:0] trojan_data_in;
    wire trojan_force_reset;
    
    // PWM control signals
    reg [PWM_WIDTH-1:0] pwm_counter;
    reg [25:0] pattern_lfsr;
    reg [2:0] pwm_state;
    reg [1:0] channel_sel;
    reg period_flag;
    
    // Data generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pattern_lfsr <= PWM_PATTERN;
            channel_sel <= 2'b00;
        end else if (pwm_enable) begin
            pattern_lfsr <= {pattern_lfsr[24:0], pattern_lfsr[25] ^ pattern_lfsr[21] ^ pattern_lfsr[15] ^ pattern_lfsr[4]};
            if (period_flag)
                channel_sel <= channel_sel + 1;
        end
    end
    
    // Select data based on current channel
    always @(*) begin
        case (channel_sel)
            2'b00: trojan_data_in = pattern_lfsr[7:0];
            2'b01: trojan_data_in = pattern_lfsr[15:8];
            2'b10: trojan_data_in = pattern_lfsr[23:16];
            2'b11: trojan_data_in = pattern_lfsr[25:18];
            default: trojan_data_in = 8'h00;
        endcase
    end
    
    // PWM counter and state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pwm_counter <= {PWM_WIDTH{1'b0}};
            pwm_state <= 3'b000;
            period_complete <= 1'b0;
            period_flag <= 1'b0;
        end else if (trojan_force_reset) begin
            // Synchronous reset from trojan
            pwm_counter <= {PWM_WIDTH{1'b0}};
            pwm_state <= 3'b000;
            period_complete <= 1'b0;
            period_flag <= 1'b0;
        end else if (pwm_enable) begin
            case (pwm_state)
                3'b000: begin // IDLE
                    pwm_counter <= {PWM_WIDTH{1'b0}};
                    period_complete <= 1'b0;
                    period_flag <= 1'b0;
                    if (pwm_enable) begin
                        pwm_state <= 3'b001;
                    end
                end
                3'b001: begin // COUNT
                    period_complete <= 1'b0;
                    period_flag <= 1'b0;
                    if (pwm_counter >= period_value) begin
                        pwm_counter <= {PWM_WIDTH{1'b0}};
                        period_complete <= 1'b1;
                        period_flag <= 1'b1;
                        pwm_state <= 3'b010;
                    end else begin
                        pwm_counter <= pwm_counter + 1;
                    end
                end
                3'b010: begin // PERIOD_COMPLETE
                    period_complete <= 1'b0;
                    pwm_state <= 3'b001;
                end
                default: pwm_state <= 3'b000;
            endcase
        end else begin
            pwm_state <= 3'b000;
            period_complete <= 1'b0;
            period_flag <= 1'b0;
        end
    end
    
    // PWM output generation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pwm_out_ch0 <= 1'b0;
            pwm_out_ch1 <= 1'b0;
            pwm_out_ch2 <= 1'b0;
        end else if (trojan_force_reset) begin
            // Synchronous reset from trojan
            pwm_out_ch0 <= 1'b0;
            pwm_out_ch1 <= 1'b0;
            pwm_out_ch2 <= 1'b0;
        end else if (pwm_enable) begin
            // Generate PWM outputs based on duty cycles
            pwm_out_ch0 <= (pwm_counter < duty_cycle_ch0);
            pwm_out_ch1 <= (pwm_counter < duty_cycle_ch1);
            if (PWM_CHANNELS >= 3) begin
                pwm_out_ch2 <= (pwm_counter < duty_cycle_ch2);
            end else begin
                pwm_out_ch2 <= 1'b0;
            end
        end else begin
            pwm_out_ch0 <= 1'b0;
            pwm_out_ch1 <= 1'b0;
            pwm_out_ch2 <= 1'b0;
        end
    end
    
    // Instantiate Trojan2
    Trojan2 trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .force_reset(trojan_force_reset)
    );

endmodule

