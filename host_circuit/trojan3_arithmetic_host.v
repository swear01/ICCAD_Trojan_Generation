// Arithmetic Host Circuit for Trojan3
// Fixed I/O to match Trojan3: clk, rst, data_in[15:0] -> data_out[15:0]
module trojan3_arithmetic_host #(
    parameter DATA_WIDTH = 16,   // Arithmetic unit data width
    parameter PIPELINE_STAGES = 3,  // Number of pipeline stages
    parameter [31:0] MULT_SEED = 32'hABCD1234  // Seed for data generation
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] a_in,
    input wire [DATA_WIDTH-1:0] b_in,
    input wire [1:0] op_sel,
    input wire valid_in,
    output reg [DATA_WIDTH-1:0] result_out,
    output reg valid_out
);

    // Trojan interface (fixed width)
    wire [15:0] trojan_data_in;
    wire [15:0] trojan_data_out;
    
    // Pipeline registers
    reg [DATA_WIDTH-1:0] pipe_a [0:PIPELINE_STAGES-1];
    reg [DATA_WIDTH-1:0] pipe_b [0:PIPELINE_STAGES-1];
    reg [1:0] pipe_op [0:PIPELINE_STAGES-1];
    reg [PIPELINE_STAGES-1:0] pipe_valid;
    
    // Data generation for trojan
    reg [31:0] data_gen;
    reg [DATA_WIDTH-1:0] intermediate_result;
    
    // Generate data for trojan input
    always @(posedge clk or posedge rst) begin
        if (rst)
            data_gen <= MULT_SEED;
        else if (valid_in)
            data_gen <= {data_gen[29:0], data_gen[31] ^ data_gen[21] ^ data_gen[1] ^ data_gen[0]};
    end
    
    assign trojan_data_in = data_gen[15:0];
    
    // Pipeline stage 0: Input
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pipe_a[0] <= {DATA_WIDTH{1'b0}};
            pipe_b[0] <= {DATA_WIDTH{1'b0}};
            pipe_op[0] <= 2'b00;
            pipe_valid[0] <= 1'b0;
        end else begin
            pipe_a[0] <= a_in;
            pipe_b[0] <= b_in;
            pipe_op[0] <= op_sel;
            pipe_valid[0] <= valid_in;
        end
    end
    
    // Pipeline stages 1 to N-1: Propagate
    genvar i;
    generate
        for (i = 1; i < PIPELINE_STAGES; i = i + 1) begin: pipeline_stages
            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    pipe_a[i] <= {DATA_WIDTH{1'b0}};
                    pipe_b[i] <= {DATA_WIDTH{1'b0}};
                    pipe_op[i] <= 2'b00;
                    pipe_valid[i] <= 1'b0;
                end else begin
                    pipe_a[i] <= pipe_a[i-1];
                    pipe_b[i] <= pipe_b[i-1];
                    pipe_op[i] <= pipe_op[i-1];
                    pipe_valid[i] <= pipe_valid[i-1];
                end
            end
        end
    endgenerate
    
    // Arithmetic operation
    always @(*) begin
        case (pipe_op[PIPELINE_STAGES-1])
            2'b00: intermediate_result = pipe_a[PIPELINE_STAGES-1] + pipe_b[PIPELINE_STAGES-1];
            2'b01: intermediate_result = pipe_a[PIPELINE_STAGES-1] - pipe_b[PIPELINE_STAGES-1];
            2'b10: intermediate_result = pipe_a[PIPELINE_STAGES-1] * pipe_b[PIPELINE_STAGES-1];
            2'b11: intermediate_result = pipe_a[PIPELINE_STAGES-1] & pipe_b[PIPELINE_STAGES-1];
            default: intermediate_result = {DATA_WIDTH{1'b0}};
        endcase
    end
    
    // Output stage with trojan integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result_out <= {DATA_WIDTH{1'b0}};
            valid_out <= 1'b0;
        end else begin
            // Mix arithmetic result with trojan output
            if (DATA_WIDTH >= 16)
                result_out <= intermediate_result ^ {{(DATA_WIDTH-16){1'b0}}, trojan_data_out};
            else
                result_out <= intermediate_result ^ trojan_data_out[DATA_WIDTH-1:0];
            valid_out <= pipe_valid[PIPELINE_STAGES-1];
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