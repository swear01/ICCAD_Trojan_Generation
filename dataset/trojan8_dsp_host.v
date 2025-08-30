// DSP Host Circuit for Trojan8  
// Fixed I/O to match Trojan8: a,b,c,d,e[7:0], sel[2:0] -> y[15:0]
module trojan8_dsp_host (
    input wire clk,
    input wire rst,
    input wire [7:0] sample_in,
    input wire sample_valid,
    input wire [2:0] operation_mode,
    output reg [15:0] dsp_result,
    output reg result_valid
);

    // Trojan interface (fixed width)
    wire [7:0] trojan_a, trojan_b, trojan_c, trojan_d, trojan_e;
    wire [2:0] trojan_sel;
    wire [15:0] trojan_y;
    
    // DSP state - fixed constants
    localparam COEFF_COUNT = 5;
    localparam PIPELINE_DEPTH = 3;
    localparam [39:0] DSP_SEED = 40'h123456789A;
    
    reg [39:0] coeff_gen;
    reg [7:0] coefficients [0:4];    // Fixed size
    reg [15:0] pipeline_data [0:2];  // Fixed size
    reg [2:0] pipeline_valid;        // Fixed size
    
    // Loop variable
    integer i;
    
    // Generate DSP coefficients for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            coeff_gen <= DSP_SEED;
            // Initialize coefficients
            for (i = 0; i < 5; i = i + 1) begin
                coefficients[i] <= DSP_SEED[7:0] + i[7:0];
            end
        end else if (sample_valid) begin
            coeff_gen <= {coeff_gen[38:0], coeff_gen[39] ^ coeff_gen[23] ^ coeff_gen[7]};
        end
    end
    
    assign trojan_a = coefficients[0];
    assign trojan_b = coefficients[1]; 
    assign trojan_c = coefficients[2];
    assign trojan_d = coefficients[3];
    assign trojan_e = coefficients[4];
    assign trojan_sel = operation_mode;
    
    // DSP pipeline
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 3; i = i + 1) begin
                pipeline_data[i] <= 16'h0;
            end
            pipeline_valid <= 3'b0;
        end else begin
            // Stage 0: Input
            pipeline_data[0] <= sample_in * coefficients[0];
            pipeline_valid[0] <= sample_valid;
            
            // Subsequent stages
            for (i = 1; i < 3; i = i + 1) begin
                pipeline_data[i] <= pipeline_data[i-1] + (sample_in * coefficients[i]);
                pipeline_valid[i] <= pipeline_valid[i-1];
            end
        end
    end
    
    // Output with trojan integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dsp_result <= 16'h0;
            result_valid <= 1'b0;
        end else begin
            // Mix DSP pipeline result with trojan output
            dsp_result <= pipeline_data[2] ^ trojan_y;  // Last stage
            result_valid <= pipeline_valid[2];
        end
    end
    
    // Instantiate Trojan8
    Trojan8 trojan_inst (
        .a(trojan_a),
        .b(trojan_b),
        .c(trojan_c),
        .d(trojan_d),
        .e(trojan_e),
        .sel(trojan_sel),
        .y(trojan_y)
    );

endmodule
