// DSP Host Circuit for Trojan0
// Fixed I/O to match Trojan0: key[127:0] -> load[63:0]
module trojan0_dsp_host #(
    parameter DATA_WIDTH = 16,   // DSP data width
    parameter COEFF_COUNT = 8,   // Number of filter coefficients
    parameter PIPELINE_STAGES = 3, // Pipeline depth
    parameter [127:0] KEY_INIT = 128'h0FEDCBA987654321123456789ABCDEF0  // DSP key seed
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] sample_in,
    input wire sample_valid,
    input wire [DATA_WIDTH-1:0] coefficients [0:COEFF_COUNT-1],
    output reg [DATA_WIDTH*2-1:0] dsp_out,
    output reg result_valid
);

    // Trojan interface (fixed width)
    wire [127:0] trojan_key;
    wire [63:0] trojan_load;
    
    // DSP pipeline state
    reg [DATA_WIDTH-1:0] delay_line [0:COEFF_COUNT-1];
    reg [DATA_WIDTH*2-1:0] mac_result;
    reg [127:0] key_generator;
    reg [DATA_WIDTH*2-1:0] pipeline [0:PIPELINE_STAGES-1];
    reg [PIPELINE_STAGES-1:0] valid_pipeline;
    reg [31:0] accumulator;
    
    // Key generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst)
            key_generator <= KEY_INIT;
        else if (sample_valid)
            key_generator <= {key_generator[119:0], key_generator[127:120] ^ sample_in[7:0]};
    end
    
    assign trojan_key = key_generator;
    
    // FIR filter implementation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Initialize delay line
            for (integer i = 0; i < COEFF_COUNT; i = i + 1) begin
                delay_line[i] <= {DATA_WIDTH{1'b0}};
            end
        end else if (sample_valid) begin
            // Shift delay line
            delay_line[0] <= sample_in;
            for (integer i = 1; i < COEFF_COUNT; i = i + 1) begin
                delay_line[i] <= delay_line[i-1];
            end
        end
    end
    
    // MAC operation
    always @(*) begin
        mac_result = {DATA_WIDTH*2{1'b0}};
        for (integer i = 0; i < COEFF_COUNT; i = i + 1) begin
            mac_result = mac_result + (delay_line[i] * coefficients[i]);
        end
    end
    
    // Pipeline stages
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (integer i = 0; i < PIPELINE_STAGES; i = i + 1) begin
                pipeline[i] <= {DATA_WIDTH*2{1'b0}};
            end
            valid_pipeline <= {PIPELINE_STAGES{1'b0}};
        end else begin
            // Pipeline stage 0
            pipeline[0] <= mac_result;
            valid_pipeline[0] <= sample_valid;
            
            // Propagate through pipeline
            for (integer i = 1; i < PIPELINE_STAGES; i = i + 1) begin
                pipeline[i] <= pipeline[i-1];
                valid_pipeline[i] <= valid_pipeline[i-1];
            end
        end
    end
    
    // Output stage with trojan load integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dsp_out <= {DATA_WIDTH*2{1'b0}};
            result_valid <= 1'b0;
        end else begin
            // Mix DSP result with trojan load (safe width handling)
            dsp_out <= pipeline[PIPELINE_STAGES-1] ^ trojan_load[DATA_WIDTH*2-1:0];
            result_valid <= valid_pipeline[PIPELINE_STAGES-1];
        end
    end
    
    // Instantiate Trojan0
    Trojan0 trojan_inst (
        .clk(clk),
        .rst(rst),
        .key(trojan_key),
        .load(trojan_load)
    );

endmodule
