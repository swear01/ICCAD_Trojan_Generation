// Corrected Vector/ALU Processing Unit Host Circuit for Trojan9
// Design: Single ALU, processing one element per clock cycle.
// Trojan: Injects fault by overriding opcode, or corrupting input data.
module trojan9_alu_host #(
    parameter [79:0] VECTOR_PATTERN = 80'h123456789ABCDEF01234
)(
    input wire clk,
    input wire rst,
    input wire [15:0] vector_a_in,
    input wire [15:0] vector_b_in,
    input wire [1:0] vector_op,          // 0=add, 1=sub, 2=mul, 3=dot
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
    reg [15:0] vector_a [0:15];
    reg [15:0] vector_b [0:15];
    reg [15:0] result_vector [0:15];
    reg [79:0] vector_gen;
    reg [2:0] vector_state;
    reg [4:0] element_index;
    reg [31:0] dot_accumulator;

    // Loop variable for initialization
    integer i;

    // Vector controller
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vector_gen      <= VECTOR_PATTERN;
            vector_state    <= 3'h0; // IDLE
            element_index   <= 5'h0;
            dot_accumulator <= 32'h0;
            result_out      <= 16'h0;
            compute_done    <= 1'b0;

            // Initialize vectors using non-blocking assignments
            for (i = 0; i < 16; i = i + 1) begin
                vector_a[i]      <= VECTOR_PATTERN[15:0] ^ i[15:0];
                vector_b[i]      <= VECTOR_PATTERN[31:16] ^ i[15:0];
                result_vector[i] <= 16'h0;
            end
        end else begin
            vector_gen <= {vector_gen[78:0], vector_gen[79]};
            compute_done <= 1'b0;

            case (vector_state)
                3'h0: begin // IDLE
                    if (vector_load_a) begin
                        // Trojan can corrupt data on load
                        vector_a[vector_index] <= vector_a_in ^ trojan_y;
                    end else if (vector_load_b) begin
                        vector_b[vector_index] <= vector_b_in ^ trojan_y;
                    end else if (compute_start) begin
                        element_index   <= 5'h0;
                        dot_accumulator <= 32'h0;
                        vector_state    <= 3'h1; // Move to COMPUTE
                    end
                end

                3'h1: begin // COMPUTE
                    if (element_index < 16) begin
                        // Trojan can override the operation
                        // e.g., if trojan_y[15] is high, use trojan_y[1:0] as op
                        case (trojan_y[15] ? trojan_y[1:0] : vector_op)
                            2'b00: // ADD
                                result_vector[element_index[3:0]] <= vector_a[element_index[3:0]] + vector_b[element_index[3:0]];
                            2'b01: // SUB
                                result_vector[element_index[3:0]] <= vector_a[element_index[3:0]] - vector_b[element_index[3:0]];
                            2'b10: // MUL
                                result_vector[element_index[3:0]] <= vector_a[element_index[3:0]] * vector_b[element_index[3:0]];
                            2'b11: // DOT_PRODUCT_STEP
                                dot_accumulator <= dot_accumulator + (vector_a[element_index[3:0]] * vector_b[element_index[3:0]]);
                            default:
                                result_vector[element_index[3:0]] <= 16'hDEAD;
                        endcase
                        element_index <= element_index + 1;
                    end else begin
                        vector_state <= 3'h2; // Move to FINISH
                    end
                end

                3'h2: begin // FINISH
                    // For dot product, output the accumulator. Otherwise, output the last element of the result vector.
                    if (vector_op == 2'b11) begin
                        result_out <= dot_accumulator[15:0];
                    end else begin
                        result_out <= result_vector[15];
                    end
                    compute_done <= 1'b1;
                    vector_state <= 3'h0; // Return to IDLE
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
