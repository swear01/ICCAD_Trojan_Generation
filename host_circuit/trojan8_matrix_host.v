// Matrix Host Circuit for Trojan8
// Fixed I/O to match Trojan8: a,b,c,d,e[7:0], sel[2:0] -> y[15:0]
module trojan8_matrix_host #(
    parameter MATRIX_SIZE = 4,   // Matrix dimension (4x4)
    parameter MAC_UNITS = 2,     // Number of MAC units
    parameter [95:0] MAT_PATTERN = 96'h123456789ABCDEF012345678  // Pattern for matrix data generation
)(
    input wire clk,
    input wire rst,
    input wire [127:0] matrix_a_flat,  // Flattened matrix A (4x4x8 = 128 bits max)
    input wire [127:0] matrix_b_flat,  // Flattened matrix B (4x4x8 = 128 bits max)
    input wire [2:0] matrix_op,
    input wire matrix_start,
    output reg [255:0] matrix_result_flat,  // Flattened result (4x4x16 = 256 bits max)
    output reg matrix_ready
);
    
    // Calculate actual bit widths
    localparam INPUT_WIDTH = 8 * MATRIX_SIZE * MATRIX_SIZE;
    localparam OUTPUT_WIDTH = 16 * MATRIX_SIZE * MATRIX_SIZE;

    // Trojan interface (fixed width)
    wire [7:0] trojan_a, trojan_b, trojan_c, trojan_d, trojan_e;
    wire [2:0] trojan_sel;
    wire [15:0] trojan_y;
    
    // Matrix processing state
    reg [95:0] mat_gen;
    reg [$clog2(MATRIX_SIZE)-1:0] row_index, col_index;
    reg [2:0] mat_state;
    reg [15:0] accumulator;
    
    // Helper function for flat array indexing
    function integer get_flat_index;
        input [$clog2(MATRIX_SIZE)-1:0] row;
        input [$clog2(MATRIX_SIZE)-1:0] col;
        begin
            get_flat_index = (row * MATRIX_SIZE + col) * 8;
        end
    endfunction
    
    function integer get_result_flat_index;
        input [$clog2(MATRIX_SIZE)-1:0] row;
        input [$clog2(MATRIX_SIZE)-1:0] col;
        begin
            get_result_flat_index = (row * MATRIX_SIZE + col) * 16;
        end
    endfunction
    
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
                      matrix_a_flat[get_flat_index(row_index, col_index) +: 8] : 8'h0;
    assign trojan_b = (row_index < MATRIX_SIZE && col_index < MATRIX_SIZE) ? 
                      matrix_b_flat[get_flat_index(row_index, col_index) +: 8] : 8'h0;
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
            // Initialize result matrix (flattened)
            matrix_result_flat <= {(16*MATRIX_SIZE*MATRIX_SIZE){1'b0}};
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
                    matrix_result_flat[get_result_flat_index(row_index, col_index) +: 16] <= trojan_y;
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