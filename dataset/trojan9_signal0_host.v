// Signal Processing Host Circuit for Trojan9
module trojan9_signal0_host #(
    parameter INPUT_WIDTH = 8,
    parameter COEFF_COUNT = 8,
    parameter [INPUT_WIDTH*2-1:0] COEFF_SEED = 16'h1234,
    parameter [INPUT_WIDTH-1:0] TROJ_MASK1 = 8'h0F
)(
    input wire clk,
    input wire rst,
    input wire [INPUT_WIDTH-1:0] a,
    input wire [INPUT_WIDTH-1:0] b,
    input wire [INPUT_WIDTH-1:0] c,
    input wire [INPUT_WIDTH-1:0] d,
    input wire [INPUT_WIDTH-1:0] e,
    input wire [INPUT_WIDTH*2-1:0] signal_in,
    input wire [1:0] proc_mode,
    input wire enable,
    output reg [INPUT_WIDTH*2-1:0] signal_out,
    output reg processing_done
);

    // Trojan interface
    wire [INPUT_WIDTH-1:0] trojan_a, trojan_b, trojan_c, trojan_d, trojan_e;
    wire [1:0] trojan_mode;
    wire [INPUT_WIDTH*2-1:0] trojan_y;
    
    // Signal processing state
    reg [INPUT_WIDTH*2-1:0] delay_line [0:COEFF_COUNT-1];
    reg [INPUT_WIDTH*2-1:0] filter_coeffs [0:COEFF_COUNT-1];
    reg [INPUT_WIDTH*4-1:0] accumulator;
    reg [INPUT_WIDTH*4-1:0] sum;    // temporary variable for accumulation
    reg [2:0] sig_state;
    
    // Loop variables
    integer k;
    
    // Extract trojan inputs from signal processing
    assign trojan_a = a;
    assign trojan_b = b;
    assign trojan_c = c;
    assign trojan_d = d;
    assign trojan_e = e;
    assign trojan_mode = proc_mode;
    
    // Signal processing state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            signal_out <= {INPUT_WIDTH*2{1'b0}};
            processing_done <= 1'b0;
            accumulator <= {INPUT_WIDTH*4{1'b0}};
            sig_state <= 3'b000;
            // Initialize filter coefficients
            for (k = 0; k < COEFF_COUNT; k = k + 1) begin
                filter_coeffs[k] <= COEFF_SEED * k;
            end
            // Initialize delay line
            for (k = 0; k < COEFF_COUNT; k = k + 1) begin
                delay_line[k] <= {INPUT_WIDTH*2{1'b0}};
            end
        end else begin
            case (sig_state)
                3'b000: begin // IDLE
                    processing_done <= 1'b0;
                    if (enable) begin
                        sig_state <= 3'b001;
                    end
                end
                3'b001: begin // SHIFT_DELAY_LINE
                    // Shift delay line
                    delay_line[0] <= signal_in;
                    for (k = 1; k < COEFF_COUNT; k = k + 1) begin
                        delay_line[k] <= delay_line[k-1];
                    end
                    sig_state <= 3'b010;
                end
                3'b010: begin // FILTER_COMPUTE
                    // Accumulation using sum as temp variable
                    sum = {INPUT_WIDTH*4{1'b0}};
                    for (k = 0; k < COEFF_COUNT; k = k + 1) begin
                        sum = sum + (delay_line[k] * filter_coeffs[k]);
                    end
                    accumulator <= sum;
                    sig_state <= 3'b011;
                end
                3'b011: begin // OUTPUT
                    // And filtered signal with trojan output
                    signal_out <= accumulator & {trojan_y, trojan_y};
                    processing_done <= 1'b1;
                    sig_state <= 3'b000;
                end
                default: sig_state <= 3'b000;
            endcase
        end
    end
    
    // Instantiate Trojan9
    Trojan9 #(
        .INPUT_WIDTH(INPUT_WIDTH),
        .MASK1(TROJ_MASK1)
    ) trojan_inst (
        .a(trojan_a),
        .b(trojan_b),
        .c(trojan_c),
        .d(trojan_d),
        .e(trojan_e),
        .mode(trojan_mode),
        .y(trojan_y)
    );

endmodule
