// Matrix Host Circuit for Trojan8
// Fixed I/O to match Trojan8: a,b,c,d,e[7:0], sel[2:0] -> y[15:0]
module trojan8_matrix_host #(
    parameter MATRIX_SIZE = 4,   // Matrix dimension (4x4)
    parameter MAC_UNITS = 2,     // Number of MAC units
    parameter [95:0] MAT_PATTERN = 96'h123456789ABCDEF012345678  // Pattern for matrix data generation
)(
    input wire clk,
    input wire rst,
    input wire [7:0] matrix_a [0:MATRIX_SIZE-1][0:MATRIX_SIZE-1],
    input wire [7:0] matrix_b [0:MATRIX_SIZE-1][0:MATRIX_SIZE-1],
    input wire [2:0] matrix_op,
    input wire matrix_start,
    output reg [15:0] matrix_result [0:MATRIX_SIZE-1][0:MATRIX_SIZE-1],
    output reg matrix_ready
);

    // Trojan interface (fixed width)
    wire [7:0] trojan_a, trojan_b, trojan_c, trojan_d, trojan_e;
    wire [2:0] trojan_sel;
    wire [15:0] trojan_y;
    
    // Matrix processing state
    reg [95:0] mat_gen;
    reg [$clog2(MATRIX_SIZE)-1:0] row_index, col_index;
    reg [2:0] mat_state;
    reg [15:0] accumulator;
    
    // Loop variables
    integer m, n;
    
    // Generate matrix data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mat_gen <= MAT_PATTERN;
            row_index <= {$clog2(MATRIX_SIZE){1'b0}};
            col_index <= {$clog2(MATRIX_SIZE){1'b0}};
            accumulator <= 16'h0;
        end else if (matrix_start || (mat_state != 3'b000)) begin
            mat_gen <= {mat_gen[93:0], mat_gen[95] ^ mat_gen[63] ^ mat_gen[31]};
        end
    end
    
    // Extract trojan inputs from matrix processing
    assign trojan_a = (row_index < MATRIX_SIZE && col_index < MATRIX_SIZE) ? 
                      matrix_a[row_index][col_index] : 8'h0;
    assign trojan_b = (row_index < MATRIX_SIZE && col_index < MATRIX_SIZE) ? 
                      matrix_b[row_index][col_index] : 8'h0;
    assign trojan_c = mat_gen[31:24];
    assign trojan_d = mat_gen[23:16];
    assign trojan_e = mat_gen[15:8];
    assign trojan_sel = matrix_op;
    
    // Matrix processing state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            row_index <= {$clog2(MATRIX_SIZE){1'b0}};
            col_index <= {$clog2(MATRIX_SIZE){1'b0}};
            matrix_ready <= 1'b0;
            mat_state <= 3'b000;
            // Initialize result matrix
            for (m = 0; m < MATRIX_SIZE; m = m + 1) begin
                for (n = 0; n < MATRIX_SIZE; n = n + 1) begin
                    matrix_result[m][n] <= 16'h0;
                end
            end
        end else begin
            case (mat_state)
                3'b000: begin // IDLE
                    matrix_ready <= 1'b0;
                    if (matrix_start) begin
                        row_index <= {$clog2(MATRIX_SIZE){1'b0}};
                        col_index <= {$clog2(MATRIX_SIZE){1'b0}};
                        mat_state <= 3'b001;
                    end
                end
                3'b001: begin // COMPUTE_ELEMENT
                    // Compute matrix element with trojan output
                    matrix_result[row_index][col_index] <= trojan_y;
                    mat_state <= 3'b010;
                end
                3'b010: begin // NEXT_ELEMENT
                    if (col_index < MATRIX_SIZE-1) begin
                        col_index <= col_index + 1;
                        mat_state <= 3'b001;
                    end else begin
                        col_index <= {$clog2(MATRIX_SIZE){1'b0}};
                        if (row_index < MATRIX_SIZE-1) begin
                            row_index <= row_index + 1;
                            mat_state <= 3'b001;
                        end else begin
                            mat_state <= 3'b011;
                        end
                    end
                end
                3'b011: begin // COMPLETE
                    matrix_ready <= 1'b1;
                    mat_state <= 3'b000;
                end
                default: mat_state <= 3'b000;
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