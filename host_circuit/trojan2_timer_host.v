// Timer Host Circuit for Trojan2
// Fixed I/O to match Trojan2: clk, rst, data_in[7:0] -> force_reset
module trojan2_timer_host #(
    parameter TIMER_WIDTH = 16,   // Timer counter width
    parameter PRESCALER = 256,    // Clock prescaler value
    parameter [31:0] TIMER_SEED = 32'hCAFEBABE  // Seed for data generation
)(
    input wire clk,
    input wire rst,
    input wire [TIMER_WIDTH-1:0] timer_load,
    input wire timer_enable,
    input wire timer_reset,
    input wire [TIMER_WIDTH-1:0] compare_value,
    output reg [TIMER_WIDTH-1:0] timer_count,
    output reg timer_overflow,
    output reg timer_match,
    output reg timer_active
);

    // Trojan interface (fixed width)
    reg [7:0] trojan_data_in;
    wire trojan_force_reset;
    
    // Timer state
    reg [TIMER_WIDTH-1:0] counter;
    reg [$clog2(PRESCALER)-1:0] prescale_counter;
    reg [31:0] seed_register;
    reg [2:0] timer_state;
    reg [2:0] byte_selector;
    reg timer_en_sync;
    
    // Data generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            seed_register <= TIMER_SEED;
            byte_selector <= 3'b000;
        end else if (timer_enable || timer_active) begin
            seed_register <= {seed_register[30:0], seed_register[31] ^ seed_register[27] ^ seed_register[15] ^ seed_register[2]};
            byte_selector <= byte_selector + 1;
        end
    end
    
    // Select byte from seed for trojan data
    always @(*) begin
        case (byte_selector)
            3'b000: trojan_data_in = seed_register[7:0];
            3'b001: trojan_data_in = seed_register[15:8];
            3'b010: trojan_data_in = seed_register[23:16];
            3'b011: trojan_data_in = seed_register[31:24];
            3'b100: trojan_data_in = seed_register[7:0] ^ timer_count[7:0];
            3'b101: trojan_data_in = seed_register[15:8] ^ timer_count[TIMER_WIDTH-1:TIMER_WIDTH-8];
            3'b110: trojan_data_in = seed_register[23:16] ^ compare_value[7:0];
            3'b111: trojan_data_in = seed_register[31:24] ^ compare_value[TIMER_WIDTH-1:TIMER_WIDTH-8];
            default: trojan_data_in = 8'h00;
        endcase
    end
    
    // Prescaler
    always @(posedge clk or posedge rst) begin
        if (rst)
            prescale_counter <= {$clog2(PRESCALER){1'b0}};
        else if (trojan_force_reset)
            prescale_counter <= {$clog2(PRESCALER){1'b0}};
        else if (timer_active) begin
            if (prescale_counter >= $clog2(PRESCALER)'(PRESCALER-1))
                prescale_counter <= {$clog2(PRESCALER){1'b0}};
            else
                prescale_counter <= prescale_counter + 1;
        end
    end
    
    wire timer_tick = timer_active && (prescale_counter == {$clog2(PRESCALER){1'b0}});
    
    // Timer state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            timer_state <= 3'b000;
            counter <= {TIMER_WIDTH{1'b0}};
            timer_active <= 1'b0;
            timer_overflow <= 1'b0;
            timer_match <= 1'b0;
            timer_en_sync <= 1'b0;
        end else if (trojan_force_reset) begin
            // Synchronous reset from trojan
            timer_state <= 3'b000;
            counter <= {TIMER_WIDTH{1'b0}};
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
                        counter <= timer_load;
                        timer_state <= 3'b001;
                        timer_active <= 1'b1;
                    end else if (timer_reset) begin
                        counter <= {TIMER_WIDTH{1'b0}};
                    end
                end
                3'b001: begin // RUNNING
                    if (timer_reset || !timer_enable) begin
                        timer_state <= 3'b000;
                    end else if (timer_tick) begin
                        if (counter >= {TIMER_WIDTH{1'b1}}) begin
                            // Overflow
                            counter <= {TIMER_WIDTH{1'b0}};
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
    
    // Output timer count
    always @(posedge clk or posedge rst) begin
        if (rst)
            timer_count <= {TIMER_WIDTH{1'b0}};
        else if (trojan_force_reset)
            timer_count <= {TIMER_WIDTH{1'b0}};
        else
            timer_count <= counter;
    end
    
    // Instantiate Trojan2
    Trojan2 trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .force_reset(trojan_force_reset)
    );

endmodule

