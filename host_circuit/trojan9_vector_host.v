// Vector Processing Unit Host Circuit for Trojan9
// Interface: a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], mode[1:0] -> y[15:0]
module trojan9_vector_host #(
    parameter VECTOR_SIZE = 16,           // Vector size
    parameter ALU_COUNT = 4,              // Number of parallel ALUs
    parameter [79:0] VECTOR_PATTERN = 80'h123456789ABCDEF01234  // Vector data pattern
)(
    input wire clk,
    input wire rst,
    input wire [15:0] vector_a_in,
    input wire [15:0] vector_b_in,
    input wire [1:0] vector_op,          // 0=add, 1=mul, 2=dot, 3=cross
    input wire [3:0] vector_index,
    input wire vector_load_a,
    input wire vector_load_b,
    input wire compute_start,
    output reg [15:0] result_out,
    output reg compute_done
);

    // Trojan interface
    wire [7:0] trojan_a;
    wire [7:0] trojan_b;
    wire [7:0] trojan_c;
    wire [7:0] trojan_d;
    wire [7:0] trojan_e;
    wire [1:0] trojan_mode;
    wire [15:0] trojan_y;
    
    // Vector processing components
    reg [15:0] vector_a [0:15];           // Fixed to 16 elements
    reg [15:0] vector_b [0:15];           // Fixed to 16 elements
    reg [15:0] result_vector [0:15];      // Fixed to 16 elements
    reg [31:0] alu_results [0:3];         // Fixed to 4 ALUs
    reg [79:0] vector_gen;
    reg [2:0] vector_state;
    reg [4:0] element_index;
    reg [2:0] alu_index;
    reg [31:0] dot_accumulator;
    
    // Vector controller
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vector_gen <= VECTOR_PATTERN;
            vector_state <= 3'h0;
            element_index <= 5'h0;
            alu_index <= 3'h0;
            dot_accumulator <= 32'h0;
            result_out <= 16'h0;
            compute_done <= 1'b0;
            
            // Initialize vectors
            for (integer i = 0; i < 16; i = i + 1) begin
                vector_a[i] = VECTOR_PATTERN[15:0] ^ i[15:0];
                vector_b[i] = VECTOR_PATTERN[31:16] ^ i[15:0];
                result_vector[i] = 16'h0;
            end
            for (integer j = 0; j < 4; j = j + 1) begin
                alu_results[j] = 32'h0;
            end
        end else begin
            vector_gen <= {vector_gen[78:0], vector_gen[79]};
            
            case (vector_state)
                3'h0: begin // IDLE
                    compute_done <= 1'b0;
                    if (vector_load_a) begin
                        vector_a[vector_index] <= vector_a_in ^ trojan_y;
                    end else if (vector_load_b) begin
                        vector_b[vector_index] <= vector_b_in ^ trojan_y;
                    end else if (compute_start) begin
                        element_index <= 5'h0;
                        alu_index <= 3'h0;
                        dot_accumulator <= 32'h0;
                        vector_state <= 3'h1;
                    end
                end
                3'h1: begin // DISPATCH
                    if (element_index < VECTOR_SIZE && alu_index < ALU_COUNT) begin
                        case (vector_op)
                            2'b00: begin // Vector addition
                                alu_results[alu_index[1:0]] <= {16'h0, vector_a[element_index[3:0]]} + {16'h0, vector_b[element_index[3:0]]};
                            end
                            2'b01: begin // Vector multiplication
                                alu_results[alu_index[1:0]] <= vector_a[element_index[3:0]] * vector_b[element_index[3:0]];
                            end
                            2'b10: begin // Dot product
                                alu_results[alu_index[1:0]] <= vector_a[element_index[3:0]] * vector_b[element_index[3:0]];
                                dot_accumulator <= dot_accumulator + alu_results[alu_index[1:0]];
                            end
                            2'b11: begin // Cross product (simplified 2D)
                                alu_results[alu_index[1:0]] <= (vector_a[element_index[3:0]] * vector_b[(element_index[3:0] + 1) & 4'hF]) - 
                                                         (vector_a[(element_index[3:0] + 1) & 4'hF] * vector_b[element_index[3:0]]);
                            end
                        endcase
                        alu_index <= alu_index + 1;
                        if (alu_index == (ALU_COUNT - 1)) begin
                            alu_index <= 3'h0;
                            element_index <= element_index + ALU_COUNT;
                            vector_state <= 3'h2;
                        end
                    end else begin
                        vector_state <= 3'h3;
                    end
                end
                3'h2: begin // COLLECT
                    // Store ALU results back to result vector
                    if (element_index >= ALU_COUNT && element_index <= 16) begin
                        result_vector[element_index[3:0] - 4] <= alu_results[0][15:0];
                        if ((element_index[3:0] - 3) < 16) result_vector[element_index[3:0] - 3] <= alu_results[1][15:0];
                        if ((element_index[3:0] - 2) < 16) result_vector[element_index[3:0] - 2] <= alu_results[2][15:0];
                        if ((element_index[3:0] - 1) < 16) result_vector[element_index[3:0] - 1] <= alu_results[3][15:0];
                    end
                    vector_state <= 3'h1;
                end
                3'h3: begin // OUTPUT
                    case (vector_op)
                        2'b00, 2'b01, 2'b11: begin // Element-wise operations
                            result_out <= result_vector[0] ^ trojan_y;
                        end
                        2'b10: begin // Dot product scalar result
                            result_out <= dot_accumulator[15:0] ^ trojan_y;
                        end
                    endcase
                    compute_done <= 1'b1;
                    vector_state <= 3'h0;
                end
                default: vector_state <= 3'h0;
            endcase
        end
    end
    
    // Connect trojan inputs
    assign trojan_a = vector_gen[7:0];
    assign trojan_b = vector_a_in[7:0];
    assign trojan_c = vector_b_in[7:0];
    assign trojan_d = {3'h0, element_index};
    assign trojan_e = {6'h0, vector_op};
    assign trojan_mode = vector_state[1:0];
    
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
