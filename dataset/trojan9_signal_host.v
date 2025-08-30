// Signal Processing Host Circuit for Trojan9
// Fixed I/O to match Trojan9: a,b,c,d,e[7:0], mode[1:0] -> y[15:0]
module trojan9_signal_host #(
    parameter [191:0] SIG_PATTERN = 192'h123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0  // Signal data pattern
)(
    input wire clk,
    input wire rst,
    input wire [15:0] signal_in,
    input wire [1:0] proc_mode, // 0=lowpass, 1=highpass, 2=bandpass, 3=notch
    input wire enable,
    output reg [15:0] signal_out,
    output reg processing_done
);

    // Trojan interface (fixed width)
    wire [7:0] trojan_a, trojan_b, trojan_c, trojan_d, trojan_e;
    wire [1:0] trojan_mode;
    wire [15:0] trojan_y;
    
    // Signal processing state
    reg [191:0] sig_gen;
    reg [15:0] delay_line [0:7];  // Fixed to 8 elements
    reg [15:0] filter_coeffs [0:7];  // Fixed to 8 elements
    reg [3:0] sample_counter;  // Fixed to 4 bits for counter up to 16
    reg [31:0] accumulator;
    reg [2:0] sig_state;
    
    // Loop variables
    integer k;
    
    // Generate signal processing data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sig_gen <= SIG_PATTERN;
            sample_counter <= 4'h0;
            // Initialize filter coefficients
            for (k = 0; k < 8; k = k + 1) begin
                filter_coeffs[k] <= 16'h1234 + k[15:0];
            end
            // Initialize delay line
            for (k = 0; k < 8; k = k + 1) begin
                delay_line[k] <= 16'h0000;
            end
        end else if (enable) begin
            sig_gen <= {sig_gen[190:0], sig_gen[191] ^ sig_gen[159] ^ sig_gen[127]};
            sample_counter <= sample_counter + 1;
        end
    end
    
    // Extract trojan inputs from signal processing
    assign trojan_a = sig_gen[55:48];
    assign trojan_b = sig_gen[47:40];
    assign trojan_c = sig_gen[39:32];
    assign trojan_d = sig_gen[31:24];
    assign trojan_e = sig_gen[23:16];
    assign trojan_mode = proc_mode;
    
    // Signal processing state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            signal_out <= 16'h0000;
            processing_done <= 1'b0;
            accumulator <= 32'h00000000;
            sig_state <= 3'b000;
        end else begin
            case (sig_state)
                3'b000: begin // IDLE
                    processing_done <= 1'b0;
                    if (enable) begin
                        sig_state <= 3'b001;
                    end
                end
                3'b001: begin // SHIFT_DELAY_LINE
                    // Shift delay line (manual shift for correct operation)
                    delay_line[7] <= delay_line[6];
                    delay_line[6] <= delay_line[5];
                    delay_line[5] <= delay_line[4];
                    delay_line[4] <= delay_line[3];
                    delay_line[3] <= delay_line[2];
                    delay_line[2] <= delay_line[1];
                    delay_line[1] <= delay_line[0];
                    delay_line[0] <= signal_in;
                    sig_state <= 3'b010;
                end
                3'b010: begin // FILTER_COMPUTE
                    // Simplified FIR computation (corrected accumulation)
                    accumulator <= 32'h00000000;
                    accumulator <= accumulator + (delay_line[0] * filter_coeffs[0]);
                    accumulator <= accumulator + (delay_line[1] * filter_coeffs[1]);
                    accumulator <= accumulator + (delay_line[2] * filter_coeffs[2]);
                    accumulator <= accumulator + (delay_line[3] * filter_coeffs[3]);
                    accumulator <= accumulator + (delay_line[4] * filter_coeffs[4]);
                    accumulator <= accumulator + (delay_line[5] * filter_coeffs[5]);
                    accumulator <= accumulator + (delay_line[6] * filter_coeffs[6]);
                    accumulator <= accumulator + (delay_line[7] * filter_coeffs[7]);
                    sig_state <= 3'b011;
                end
                3'b011: begin // OUTPUT
                    // Mix filtered signal with trojan output
                    signal_out <= accumulator[15:0] ^ trojan_y[15:0];
                    processing_done <= 1'b1;
                    sig_state <= 3'b000;
                end
                default: sig_state <= 3'b000;
            endcase
        end
    end
    
    // Instantiate Trojan9
    Trojan9 trojan_inst (
        .a(trojan_a),
        .b(trojan_b),
        .c(trojan_c),
        .d(trojan_d),
        .e(trojan_e),
        .mode(trojan_mode),
        .y(trojan_y)
    );

endmodule
