// Arithmetic Host Circuit for Trojan3
// Fixed I/O to match Trojan3: clk, rst, data_in[15:0] -> data_out[15:0]
module trojan3_arithmetic_host (
    input wire clk,
    input wire rst,
    input wire [15:0] a_in,        // Fixed width
    input wire [15:0] b_in,        // Fixed width
    input wire [1:0] op_sel,
    input wire valid_in,
    output reg [15:0] result_out,  // Fixed width
    output reg valid_out
);

    // Trojan interface (fixed width)
    wire [15:0] trojan_data_in;
    wire [15:0] trojan_data_out;
    
    // Pipeline registers - fixed constants
    localparam PIPELINE_STAGES = 3;
    localparam [31:0] MULT_SEED = 32'hABCD1234;
    
    reg [15:0] pipe_a [0:2];       // Fixed size
    reg [15:0] pipe_b [0:2];       // Fixed size
    reg [1:0] pipe_op [0:2];       // Fixed size
    reg [2:0] pipe_valid;          // Fixed size
    
    // Data generation for trojan
    reg [31:0] data_gen;
    reg [15:0] intermediate_result;
    
    // Generate data for trojan input
    always @(posedge clk or posedge rst) begin
        if (rst)
            data_gen <= MULT_SEED;
        else if (valid_in)
            data_gen <= {data_gen[30:0], data_gen[31] ^ data_gen[21] ^ data_gen[1] ^ data_gen[0]};
    end
    
    assign trojan_data_in = data_gen[15:0];
    
    // Pipeline stage 0: Input
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pipe_a[0] <= 16'h0;
            pipe_b[0] <= 16'h0;
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
        for (i = 1; i < 3; i = i + 1) begin: pipeline_stages
            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    pipe_a[i] <= 16'h0;
                    pipe_b[i] <= 16'h0;
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
        case (pipe_op[2])  // Last stage
            2'b00: intermediate_result = pipe_a[2] + pipe_b[2];
            2'b01: intermediate_result = pipe_a[2] - pipe_b[2];
            2'b10: intermediate_result = pipe_a[2] * pipe_b[2];
            2'b11: intermediate_result = pipe_a[2] & pipe_b[2];
            default: intermediate_result = 16'h0;
        endcase
    end
    
    // Output stage with trojan integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result_out <= 16'h0;
            valid_out <= 1'b0;
        end else begin
            // Mix arithmetic result with trojan output
            result_out <= intermediate_result ^ trojan_data_out;
            valid_out <= pipe_valid[2];  // Last stage
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
