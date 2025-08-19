// FFT Host Circuit for Trojan9
// Fixed I/O to match Trojan9: a,b,c,d,e[7:0], mode[1:0] -> y[15:0]
module trojan9_fft_host #(
    parameter FFT_SIZE = 8,      // FFT size (power of 2)
    parameter DATA_WIDTH = 16,   // FFT data width
    parameter [159:0] FFT_PATTERN = 160'h123456789ABCDEF0123456789ABCDEF012345678  // Pattern for FFT data generation
)(
    input wire clk,
    input wire rst,
    input wire [(FFT_SIZE*DATA_WIDTH)-1:0] fft_data_real_flat,  // Flattened real data
    input wire [(FFT_SIZE*DATA_WIDTH)-1:0] fft_data_imag_flat,  // Flattened imaginary data
    input wire [1:0] fft_mode, // 0=FFT, 1=IFFT, 2=DCT, 3=DST
    input wire fft_start,
    output reg [(FFT_SIZE*DATA_WIDTH)-1:0] fft_result_real_flat,  // Flattened real result
    output reg [(FFT_SIZE*DATA_WIDTH)-1:0] fft_result_imag_flat,  // Flattened imaginary result
    output reg fft_done
);

    // Trojan interface (fixed width)
    wire [7:0] trojan_a, trojan_b, trojan_c, trojan_d, trojan_e;
    wire [1:0] trojan_mode;
    wire [15:0] trojan_y;
    
    // FFT processing state
    reg [159:0] fft_gen;
    reg [$clog2(FFT_SIZE)-1:0] sample_index;
    reg [$clog2($clog2(FFT_SIZE))-1:0] stage_index;
    reg [2:0] fft_state;
    
    // Internal 2D arrays for processing
    reg [DATA_WIDTH-1:0] fft_result_real [0:FFT_SIZE-1];
    reg [DATA_WIDTH-1:0] fft_result_imag [0:FFT_SIZE-1];
    
    // Loop variables
    integer i, j;
    
    // Helper functions to access flattened arrays
    function [DATA_WIDTH-1:0] get_flat_real_input;
        input [$clog2(FFT_SIZE)-1:0] index;
        begin
            get_flat_real_input = fft_data_real_flat[index*DATA_WIDTH +: DATA_WIDTH];
        end
    endfunction
    
    function [DATA_WIDTH-1:0] get_flat_imag_input;
        input [$clog2(FFT_SIZE)-1:0] index;
        begin
            get_flat_imag_input = fft_data_imag_flat[index*DATA_WIDTH +: DATA_WIDTH];
        end
    endfunction
    
    // Update flattened output arrays
    always @(*) begin
        for (i = 0; i < FFT_SIZE; i = i + 1) begin
            fft_result_real_flat[i*DATA_WIDTH +: DATA_WIDTH] = fft_result_real[i];
            fft_result_imag_flat[i*DATA_WIDTH +: DATA_WIDTH] = fft_result_imag[i];
        end
    end
    
    // Generate FFT data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            fft_gen <= FFT_PATTERN;
            sample_index <= {$clog2(FFT_SIZE){1'b0}};
            stage_index <= {$clog2($clog2(FFT_SIZE)){1'b0}};
        end else if (fft_start || (fft_state != 3'b000)) begin
            fft_gen <= {fft_gen[157:0], fft_gen[159] ^ fft_gen[127] ^ fft_gen[95]};
        end
    end
    
    // Extract trojan inputs from FFT processing
    assign trojan_a = fft_gen[47:40];
    assign trojan_b = fft_gen[39:32];
    assign trojan_c = fft_gen[31:24];
    assign trojan_d = fft_gen[23:16];
    assign trojan_e = fft_gen[15:8];
    assign trojan_mode = fft_mode;
    
    // FFT processing state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sample_index <= {$clog2(FFT_SIZE){1'b0}};
            stage_index <= {$clog2($clog2(FFT_SIZE)){1'b0}};
            fft_done <= 1'b0;
            fft_state <= 3'b000;
            // Initialize result arrays
            for (i = 0; i < FFT_SIZE; i = i + 1) begin
                fft_result_real[i] <= 16'h0000;
                fft_result_imag[i] <= 16'h0000;
            end
        end else begin
            case (fft_state)
                3'b000: begin // IDLE
                    fft_done <= 1'b0;
                    if (fft_start) begin
                        sample_index <= {$clog2(FFT_SIZE){1'b0}};
                        stage_index <= {$clog2($clog2(FFT_SIZE)){1'b0}};
                        fft_state <= 3'b001;
                    end
                end
                3'b001: begin // BIT_REVERSE
                    // Simple bit-reverse copy (simplified)
                    fft_result_real[sample_index] <= get_flat_real_input(sample_index);
                    fft_result_imag[sample_index] <= get_flat_imag_input(sample_index);
                    
                    if (sample_index >= FFT_SIZE-1) begin
                        sample_index <= {$clog2(FFT_SIZE){1'b0}};
                        fft_state <= 3'b010;
                    end else begin
                        sample_index <= sample_index + 1;
                    end
                end
                3'b010: begin // FFT_COMPUTE
                    // Simplified butterfly computation
                    if (sample_index < FFT_SIZE) begin
                        // Mix FFT data with trojan output
                        fft_result_real[sample_index] <= fft_result_real[sample_index] ^ trojan_y;
                        fft_result_imag[sample_index] <= fft_result_imag[sample_index] ^ trojan_y;
                        sample_index <= sample_index + 1;
                    end else begin
                        if (stage_index >= $clog2(FFT_SIZE)-1) begin
                            fft_state <= 3'b011;
                        end else begin
                            stage_index <= stage_index + 1;
                            sample_index <= {$clog2(FFT_SIZE){1'b0}};
                        end
                    end
                end
                3'b011: begin // COMPLETE
                    fft_done <= 1'b1;
                    fft_state <= 3'b000;
                end
                default: fft_state <= 3'b000;
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