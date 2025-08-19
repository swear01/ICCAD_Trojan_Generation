// Filter Host Circuit for Trojan3
// Fixed I/O to match Trojan3: clk, rst, data_in[15:0] -> data_out[15:0]
module trojan3_filter_host #(
    parameter TAP_WIDTH = 8,     // Filter tap width
    parameter NUM_TAPS = 4,      // Number of filter taps
    parameter [63:0] COEFF_SEED = 64'h123456789ABCDEF0  // Seed for coefficient generation
)(
    input wire clk,
    input wire rst,
    input wire signed [TAP_WIDTH-1:0] sample_in,
    input wire sample_valid,
    output reg signed [TAP_WIDTH-1:0] filtered_out,
    output reg output_valid
);

    // Trojan interface (fixed width)
    wire [15:0] trojan_data_in;
    wire [15:0] trojan_data_out;
    
    // Filter taps and coefficients
    reg signed [TAP_WIDTH-1:0] taps [0:NUM_TAPS-1];
    reg signed [TAP_WIDTH-1:0] coeffs [0:NUM_TAPS-1];
    reg signed [TAP_WIDTH+$clog2(NUM_TAPS)-1:0] accumulator;
    
    // Coefficient generation for trojan data
    reg [63:0] coeff_gen;
    reg [2:0] tap_idx;
    
    // Generate coefficients and trojan data
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            coeff_gen <= COEFF_SEED;
            tap_idx <= 3'b0;
        end else if (sample_valid) begin
            coeff_gen <= {coeff_gen[61:0], coeff_gen[63] ^ coeff_gen[41] ^ coeff_gen[5]};
            tap_idx <= tap_idx + 1;
        end
    end
    
    assign trojan_data_in = coeff_gen[15:0];
    
    // Initialize coefficients
    integer j;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (j = 0; j < NUM_TAPS; j = j + 1) begin
                coeffs[j] <= coeff_gen[TAP_WIDTH-1:0] + j[TAP_WIDTH-1:0];
            end
        end
    end
    
    // Shift register (taps)
    integer k;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (k = 0; k < NUM_TAPS; k = k + 1) begin
                taps[k] <= {TAP_WIDTH{1'b0}};
            end
        end else if (sample_valid) begin
            taps[0] <= sample_in;
            for (k = 1; k < NUM_TAPS; k = k + 1) begin
                taps[k] <= taps[k-1];
            end
        end
    end
    
    // FIR filter computation
    integer l;
    always @(*) begin
        accumulator = {(TAP_WIDTH+$clog2(NUM_TAPS)){1'b0}};
        for (l = 0; l < NUM_TAPS; l = l + 1) begin
            accumulator = accumulator + (taps[l] * coeffs[l]);
        end
    end
    
    // Output with trojan integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            filtered_out <= {TAP_WIDTH{1'b0}};
            output_valid <= 1'b0;
        end else begin
            // Mix filter output with trojan output
            if (TAP_WIDTH >= 16)
                filtered_out <= accumulator[TAP_WIDTH-1:0] ^ trojan_data_out[TAP_WIDTH-1:0];
            else
                filtered_out <= accumulator[TAP_WIDTH-1:0] ^ trojan_data_out[TAP_WIDTH-1:0];
            output_valid <= sample_valid;
        end
    end
    
    // Instantiate Trojan3
    Trojan3 trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .data_out(trojan_data_out)
    );

endmodule