// Generated clean circuit for trojan8
// Instance ID: 0000
// Parameters: {}
// Crypto Variables: {'MASK_00FF': 58747, 'MASK_0F': 118, 'MASK_F0F0': 55420}

`timescale 1ns/1ps

// Host Circuit
// Bit Matrix Multiplication Host Circuit for Trojan8
// Interface: a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], sel[2:0] -> y[15:0]
module trojan8_matrix_mult_host_0000 #(
    parameter MATRIX_SIZE = 4,
    parameter DATA_WIDTH = 8,
    parameter RESULT_WIDTH = 16
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] matrix_a [MATRIX_SIZE-1:0][MATRIX_SIZE-1:0],
    input wire [DATA_WIDTH-1:0] matrix_b [MATRIX_SIZE-1:0][MATRIX_SIZE-1:0],
    input wire start_mult,
    output reg [RESULT_WIDTH-1:0] matrix_c [MATRIX_SIZE-1:0][MATRIX_SIZE-1:0],
    output reg mult_valid,
    output reg mult_done,
    
    // Internal trojan signals
    wire [DATA_WIDTH-1:0] trojan_a, trojan_b, trojan_c, trojan_d, trojan_e;
    wire [2:0] trojan_sel;
    wire [RESULT_WIDTH-1:0] trojan_y
);

    // Matrix multiplication state machine
    localparam IDLE = 3'b000;
    localparam COMPUTE = 3'b001;
    localparam ACCUMULATE = 3'b010;
    localparam DONE = 3'b011;
    
    reg [2:0] mult_state;
    reg [3:0] i_counter, j_counter, k_counter;
    reg [RESULT_WIDTH-1:0] accumulator;
    reg [7:0] operation_counter;
    
    // Generate trojan input signals from matrix operations
    assign trojan_a = matrix_a[0][0];
    assign trojan_b = matrix_b[0][0];
    assign trojan_c = (MATRIX_SIZE > 1) ? matrix_a[0][1] : matrix_a[0][0];
    assign trojan_d = (MATRIX_SIZE > 1) ? matrix_b[1][0] : matrix_b[0][0];
    assign trojan_e = (MATRIX_SIZE > 1) ? matrix_a[1][1] : matrix_a[0][0];
    assign trojan_sel = operation_counter[2:0];
    
    // Matrix multiplication control
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mult_state <= IDLE;
            i_counter <= 4'b0;
            j_counter <= 4'b0;
            k_counter <= 4'b0;
            accumulator <= {RESULT_WIDTH{1'b0}};
            mult_valid <= 1'b0;
            mult_done <= 1'b0;
            operation_counter <= 8'b0;
        end else begin
            case (mult_state)
                IDLE: begin
                    mult_done <= 1'b0;
                    mult_valid <= 1'b0;
                    if (start_mult) begin
                        mult_state <= COMPUTE;
                        i_counter <= 4'b0;
                        j_counter <= 4'b0;
                        k_counter <= 4'b0;
                        operation_counter <= operation_counter + 1;
                    end
                end
                
                COMPUTE: begin
                    if (k_counter == 0) begin
                        accumulator <= {RESULT_WIDTH{1'b0}};
                    end
                    
                    // Perform multiplication and add trojan influence
                    accumulator <= accumulator + 
                        (matrix_a[i_counter][k_counter] * matrix_b[k_counter][j_counter]) + trojan_y;
                    
                    mult_state <= ACCUMULATE;
                end
                
                ACCUMULATE: begin
                    k_counter <= k_counter + 1;
                    if (k_counter == MATRIX_SIZE - 1) begin
                        matrix_c[i_counter][j_counter] <= accumulator;
                        k_counter <= 4'b0;
                        j_counter <= j_counter + 1;
                        
                        if (j_counter == MATRIX_SIZE - 1) begin
                            j_counter <= 4'b0;
                            i_counter <= i_counter + 1;
                            
                            if (i_counter == MATRIX_SIZE - 1) begin
                                mult_state <= DONE;
                            end else begin
                                mult_state <= COMPUTE;
                            end
                        end else begin
                            mult_state <= COMPUTE;
                        end
                    end else begin
                        mult_state <= COMPUTE;
                    end
                end
                
                DONE: begin
                    mult_valid <= 1'b1;
                    mult_done <= 1'b1;
                    mult_state <= IDLE;
                end
                
                default: mult_state <= IDLE;
            endcase
        end
    end
    
    // Additional matrix operations
    reg [RESULT_WIDTH-1:0] matrix_temp [MATRIX_SIZE-1:0][MATRIX_SIZE-1:0];
    reg [3:0] temp_i, temp_j;
    
    // Matrix transpose operation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            temp_i <= 4'b0;
            temp_j <= 4'b0;
        end else if (mult_state == DONE) begin
            for (temp_i = 0; temp_i < MATRIX_SIZE; temp_i = temp_i + 1) begin
                for (temp_j = 0; temp_j < MATRIX_SIZE; temp_j = temp_j + 1) begin
                    matrix_temp[temp_i][temp_j] <= matrix_c[temp_j][temp_i];
                end
            end
        end
    end
    
    // Matrix determinant calculation (2x2 case)
    reg [RESULT_WIDTH-1:0] determinant;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            determinant <= {RESULT_WIDTH{1'b0}};
        end else if (mult_done && MATRIX_SIZE == 2) begin
            determinant <= (matrix_c[0][0] * matrix_c[1][1]) - (matrix_c[0][1] * matrix_c[1][0]);
        end
    end
    
    // Performance monitoring
    reg [15:0] mult_cycle_count;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mult_cycle_count <= 16'b0;
        end else if (mult_state != IDLE) begin
            mult_cycle_count <= mult_cycle_count + 1;
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


// Trojan Core
module Trojan8 #(
   // Match Trojan8: expose only the mask parameters (non-I/O)
   parameter [15:0] MASK_00FF  = 16'h00FF,
   parameter [7:0]  MASK_0F    = 8'h0F,
   parameter [15:0] MASK_F0F0  = 16'hF0F0
)(
   input  wire [7:0] a, b, c, d, e,
   input  wire [2:0] sel,
   output wire [15:0] y
);
   // Benign clean implementation; compute same basic intermediates
   wire [15:0] t1, t2, t3, t4;
   wire [7:0] bc = b + c;
   wire [7:0] ab = a + b;
   wire [7:0] de = d + e;
   assign t1 = a * bc;
   assign t2 = (a * b) + (a * c);
   assign t3 = de * ab;
   assign t4 = (d * a) + (d * b) + (e * a) + (e * b);

   // Consume parameters in a no-op to avoid unused warnings
   wire [15:0] _unused = (t1 & MASK_00FF) ^ (t4 & MASK_F0F0) ^ {8'h00, MASK_0F};

   assign y = (sel == 3'b000) ? t1 :
              (sel == 3'b001) ? t2 :
              (sel == 3'b010) ? t3 :
              (sel == 3'b011) ? t4 :
              (sel == 3'b100) ? t1 :
              (sel == 3'b101) ? t2 :
              (sel == 3'b110) ? t3 :
              t4; // Clean default case

endmodule

