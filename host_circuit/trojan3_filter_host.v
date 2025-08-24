// Filter Host Circuit for Trojan3
// Fixed I/O to match Trojan3: clk, rst, data_in[15:0] -> data_out[15:0]
module trojan3_filter_host (
    input wire clk,
    input wire rst,
    input wire signed [7:0] sample_in,    // Fixed width
    input wire sample_valid,
    output reg signed [7:0] filtered_out, // Fixed width
    output reg output_valid
);

    // Trojan interface (fixed width)
    wire [15:0] trojan_data_in;
    wire [15:0] trojan_data_out;
    
    // Filter taps and coefficients - fixed constants  
    localparam NUM_TAPS = 4;
    localparam [63:0] COEFF_SEED = 64'h123456789ABCDEF0;
    
    reg signed [7:0] taps [0:3];      // Fixed size
    reg signed [7:0] coeffs [0:3];    // Fixed size
    wire signed [9:0] accumulator;    // Fixed size: 8 + $clog2(4) = 8 + 2 = 10
    
    // Coefficient generation for trojan data
    reg [63:0] coeff_gen;
    reg [2:0] tap_idx;
    
    // Generate coefficients and trojan data
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            coeff_gen <= COEFF_SEED;
            tap_idx <= 3'b0;
        end else if (sample_valid) begin
            coeff_gen <= {coeff_gen[62:0], coeff_gen[63] ^ coeff_gen[41] ^ coeff_gen[5]};
            tap_idx <= tap_idx + 1;
        end
    end
    
    assign trojan_data_in = coeff_gen[15:0];
    
    // Initialize coefficients
    integer j;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (j = 0; j < 4; j = j + 1) begin
                coeffs[j] <= COEFF_SEED[7:0] + j[7:0];
            end
        end else if (sample_valid) begin
            for (j = 0; j < 4; j = j + 1) begin
                coeffs[j] <= coeff_gen[7:0] + j[7:0];
            end
        end
    end
    
    // Shift register (taps)
    integer k;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (k = 0; k < 4; k = k + 1) begin
                taps[k] <= 8'h0;
            end
        end else if (sample_valid) begin
            taps[0] <= sample_in;
            for (k = 1; k < 4; k = k + 1) begin
                taps[k] <= taps[k-1];
            end
        end
    end
    
    // FIR filter computation - using explicit calculation to avoid latch
    assign accumulator = (taps[0] * coeffs[0]) + (taps[1] * coeffs[1]) + 
                        (taps[2] * coeffs[2]) + (taps[3] * coeffs[3]);
    
    // Output with trojan integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            filtered_out <= 8'h0;
            output_valid <= 1'b0;
        end else begin
            // Mix filter output with trojan output
            filtered_out <= accumulator[7:0] ^ trojan_data_out[7:0];
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
