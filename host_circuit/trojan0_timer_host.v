// Timer Host Circuit for Trojan0
// Fixed I/O to match Trojan0: key[127:0] -> load[63:0]
module trojan0_timer_host #(
    parameter TIMER_WIDTH = 32,  // Timer counter width
    parameter PRESCALER = 1000,  // Clock prescaler value
    parameter [127:0] KEY_INIT = 128'hF1EE70123456789ABCDEFF1EE7012444  // Timer key seed
)(
    input wire clk,
    input wire rst,
    input wire [TIMER_WIDTH-1:0] timer_load,
    input wire timer_start,
    input wire timer_stop,
    input wire timer_pause,
    output reg [TIMER_WIDTH-1:0] timer_value,
    output reg timer_overflow,
    output reg timer_match,
    output reg timer_active
);

    // Trojan interface (fixed width)
    wire [127:0] trojan_key;
    wire [63:0] trojan_load;
    
    // Timer state
    reg [TIMER_WIDTH-1:0] counter;
    reg [TIMER_WIDTH-1:0] match_value;
    reg [127:0] key_generator;
    reg [15:0] prescaler_counter;
    reg [2:0] timer_state;
    reg timer_enabled;
    
    // Key generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst)
            key_generator <= KEY_INIT;
        else if (timer_start || timer_overflow)
            key_generator <= {key_generator[95:0], key_generator[127:96] ^ counter[31:0]};
    end
    
    assign trojan_key = key_generator;
    
    // Prescaler
    always @(posedge clk or posedge rst) begin
        if (rst)
            prescaler_counter <= 16'h0;
        else if (timer_enabled && (prescaler_counter >= PRESCALER-1))
            prescaler_counter <= 16'h0;
        else if (timer_enabled)
            prescaler_counter <= prescaler_counter + 1;
    end
    
    wire timer_tick = timer_enabled && (prescaler_counter == 16'h0);
    
    // Timer state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            timer_state <= 3'b000;
            timer_enabled <= 1'b0;
            timer_active <= 1'b0;
            counter <= {TIMER_WIDTH{1'b0}};
            match_value <= {TIMER_WIDTH{1'b0}};
            timer_overflow <= 1'b0;
            timer_match <= 1'b0;
        end else begin
            case (timer_state)
                3'b000: begin // IDLE
                    timer_active <= 1'b0;
                    timer_enabled <= 1'b0;
                    timer_overflow <= 1'b0;
                    timer_match <= 1'b0;
                    if (timer_start) begin
                        counter <= timer_load;
                        match_value <= timer_load ^ trojan_load[TIMER_WIDTH-1:0];
                        timer_enabled <= 1'b1;
                        timer_active <= 1'b1;
                        timer_state <= 3'b001;
                    end
                end
                3'b001: begin // RUNNING
                    if (timer_stop) begin
                        timer_state <= 3'b000;
                    end else if (timer_pause) begin
                        timer_enabled <= 1'b0;
                        timer_state <= 3'b010;
                    end else if (timer_tick) begin
                        if (counter == {TIMER_WIDTH{1'b1}}) begin
                            // Overflow
                            counter <= {TIMER_WIDTH{1'b0}};
                            timer_overflow <= 1'b1;
                            timer_state <= 3'b011;
                        end else begin
                            counter <= counter + 1;
                            // Check for match
                            if ((counter + 1) == match_value) begin
                                timer_match <= 1'b1;
                            end
                        end
                    end
                end
                3'b010: begin // PAUSED
                    if (timer_stop) begin
                        timer_state <= 3'b000;
                    end else if (!timer_pause) begin
                        timer_enabled <= 1'b1;
                        timer_state <= 3'b001;
                    end
                end
                3'b011: begin // OVERFLOW
                    timer_overflow <= 1'b0;
                    timer_state <= 3'b000;
                end
                default: timer_state <= 3'b000;
            endcase
        end
    end
    
    // Output timer value
    always @(posedge clk or posedge rst) begin
        if (rst)
            timer_value <= {TIMER_WIDTH{1'b0}};
        else
            timer_value <= counter;
    end
    
    // Instantiate Trojan0
    Trojan0 trojan_inst (
        .clk(clk),
        .rst(rst),
        .key(trojan_key),
        .load(trojan_load)
    );

endmodule
