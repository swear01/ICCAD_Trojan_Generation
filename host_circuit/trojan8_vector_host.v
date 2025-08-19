// Vector Host Circuit for Trojan8
// Fixed I/O to match Trojan8: a,b,c,d,e[7:0], sel[2:0] -> y[15:0]
module trojan8_vector_host #(
    parameter VECTOR_SIZE = 8,   // Vector processing size
    parameter ALU_COUNT = 4,     // Number of parallel ALUs
    parameter [63:0] VEC_PATTERN = 64'h123456789ABCDEF0  // Pattern for vector data generation
)(
    input wire clk,
    input wire rst,
    input wire [127:0] vector_a_flat,  // Flattened vector A (max 16x8 = 128 bits)
    input wire [127:0] vector_b_flat,  // Flattened vector B (max 16x8 = 128 bits)
    input wire [2:0] vector_op,
    input wire compute_enable,
    output reg [255:0] vector_result_flat,  // Flattened result (max 16x16 = 256 bits)
    output reg compute_done
);

    // Calculate actual bit widths
    localparam INPUT_WIDTH = 8 * VECTOR_SIZE;
    localparam OUTPUT_WIDTH = 16 * VECTOR_SIZE;

    // Trojan interface (fixed width)
    wire [7:0] trojan_a, trojan_b, trojan_c, trojan_d, trojan_e;
    wire [2:0] trojan_sel;
    wire [15:0] trojan_y;
    
    // Vector processing state
    reg [63:0] vec_gen;
    reg [7:0] alu_inputs [0:ALU_COUNT-1][0:4]; // 5 inputs per ALU
    reg [$clog2(VECTOR_SIZE)-1:0] process_index;
    reg [2:0] vec_state;
    
    // Loop variables
    integer j, k;
    
    // Generate vector data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vec_gen <= VEC_PATTERN;
            process_index <= {$clog2(VECTOR_SIZE){1'b0}};
            // Initialize ALU inputs
            for (j = 0; j < ALU_COUNT; j = j + 1) begin
                for (k = 0; k < 5; k = k + 1) begin
                    alu_inputs[j][k] <= VEC_PATTERN[7:0] + j[7:0] + k[7:0];
                end
            end
        end else if (compute_enable) begin
            vec_gen <= {vec_gen[61:0], vec_gen[63] ^ vec_gen[31] ^ vec_gen[15]};
        end
    end
    
    // Extract trojan inputs from vector processing
    assign trojan_a = (process_index < VECTOR_SIZE) ? vector_a_flat[process_index*8 +: 8] : 8'h0;
    assign trojan_b = (process_index < VECTOR_SIZE) ? vector_b_flat[process_index*8 +: 8] : 8'h0;
    assign trojan_c = vec_gen[23:16];
    assign trojan_d = vec_gen[15:8];
    assign trojan_e = vec_gen[7:0];
    assign trojan_sel = vector_op;
    
    // Vector processing state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            process_index <= {$clog2(VECTOR_SIZE){1'b0}};
            compute_done <= 1'b0;
            vec_state <= 3'b000;
            // Initialize result vector (flattened)
            vector_result_flat <= {(16*VECTOR_SIZE){1'b0}};
        end else begin
            case (vec_state)
                3'b000: begin // IDLE
                    compute_done <= 1'b0;
                    if (compute_enable) begin
                        process_index <= {$clog2(VECTOR_SIZE){1'b0}};
                        vec_state <= 3'b001;
                    end
                end
                3'b001: begin // COMPUTE
                    // Process vector element with trojan output
                    if (process_index < VECTOR_SIZE) begin
                        vector_result_flat[process_index*16 +: 16] <= trojan_y;
                        process_index <= process_index + 1;
                    end else begin
                        vec_state <= 3'b010;
                    end
                end
                3'b010: begin // COMPLETE
                    compute_done <= 1'b1;
                    vec_state <= 3'b000;
                end
                default: vec_state <= 3'b000;
            endcase
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