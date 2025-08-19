// Generated clean circuit for trojan9
// Instance ID: 0000
// Parameters: {}
// Crypto Variables: {'COMPUTATION_BIAS': 23550}

`timescale 1ns/1ps

// Host Circuit
// Pipelined CORDIC Host Circuit for Trojan9
// Interface: a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], mode[1:0] -> y[15:0]
module trojan9_cordic_host_0000 #(
    parameter DATA_WIDTH = 16,
    parameter ANGLE_WIDTH = 16,
    parameter ITERATIONS = 8,
    parameter RESULT_WIDTH = 24
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] x_in,
    input wire [DATA_WIDTH-1:0] y_in,
    input wire [ANGLE_WIDTH-1:0] angle_in,
    input wire [1:0] cordic_mode, // 00: rotation, 01: vectoring, 10: sin/cos, 11: arctan
    input wire cordic_start,
    output reg [DATA_WIDTH-1:0] x_out,
    output reg [DATA_WIDTH-1:0] y_out,
    output reg [ANGLE_WIDTH-1:0] angle_out,
    output reg cordic_valid,
    output reg cordic_done,
    
    // Internal trojan signals
    wire [DATA_WIDTH-1:0] trojan_a, trojan_b, trojan_c, trojan_d, trojan_e;
    wire [1:0] trojan_mode;
    wire [RESULT_WIDTH-1:0] trojan_y
);

    // CORDIC pipeline stages
    reg [DATA_WIDTH-1:0] x_stage [ITERATIONS:0];
    reg [DATA_WIDTH-1:0] y_stage [ITERATIONS:0];
    reg [ANGLE_WIDTH-1:0] z_stage [ITERATIONS:0];
    reg [1:0] mode_stage [ITERATIONS:0];
    reg valid_stage [ITERATIONS:0];
    
    // CORDIC LUT for angles - generate based on ANGLE_WIDTH
    reg [ANGLE_WIDTH-1:0] cordic_lut [ITERATIONS-1:0];
    initial begin
        // Scale CORDIC constants based on ANGLE_WIDTH
        if (ANGLE_WIDTH >= 16) begin
            if (ITERATIONS > 0) cordic_lut[0] = {{(ANGLE_WIDTH-16){1'b0}}, 16'h2000}; // atan(2^-0) * 2^14
            if (ITERATIONS > 1) cordic_lut[1] = {{(ANGLE_WIDTH-16){1'b0}}, 16'h12E4}; // atan(2^-1) * 2^14
            if (ITERATIONS > 2) cordic_lut[2] = {{(ANGLE_WIDTH-16){1'b0}}, 16'h09FB}; // atan(2^-2) * 2^14
            if (ITERATIONS > 3) cordic_lut[3] = {{(ANGLE_WIDTH-16){1'b0}}, 16'h0511}; // atan(2^-3) * 2^14
            if (ITERATIONS > 4) cordic_lut[4] = {{(ANGLE_WIDTH-16){1'b0}}, 16'h028B}; // atan(2^-4) * 2^14
            if (ITERATIONS > 5) cordic_lut[5] = {{(ANGLE_WIDTH-16){1'b0}}, 16'h0146}; // atan(2^-5) * 2^14
            if (ITERATIONS > 6) cordic_lut[6] = {{(ANGLE_WIDTH-16){1'b0}}, 16'h00A3}; // atan(2^-6) * 2^14
            if (ITERATIONS > 7) cordic_lut[7] = {{(ANGLE_WIDTH-16){1'b0}}, 16'h0051}; // atan(2^-7) * 2^14
        end else begin
            // For smaller ANGLE_WIDTH, use proportionally scaled values
            if (ITERATIONS > 0) cordic_lut[0] = (16'h2000 >> (16 - ANGLE_WIDTH));
            if (ITERATIONS > 1) cordic_lut[1] = (16'h12E4 >> (16 - ANGLE_WIDTH));
            if (ITERATIONS > 2) cordic_lut[2] = (16'h09FB >> (16 - ANGLE_WIDTH));
            if (ITERATIONS > 3) cordic_lut[3] = (16'h0511 >> (16 - ANGLE_WIDTH));
            if (ITERATIONS > 4) cordic_lut[4] = (16'h028B >> (16 - ANGLE_WIDTH));
            if (ITERATIONS > 5) cordic_lut[5] = (16'h0146 >> (16 - ANGLE_WIDTH));
            if (ITERATIONS > 6) cordic_lut[6] = (16'h00A3 >> (16 - ANGLE_WIDTH));
            if (ITERATIONS > 7) cordic_lut[7] = (16'h0051 >> (16 - ANGLE_WIDTH));
        end
    end
    
    // Generate trojan signals from CORDIC operations (width-safe)
    generate
        if (DATA_WIDTH >= 8) begin
            assign trojan_a = x_stage[0];
            assign trojan_b = y_stage[0];
            assign trojan_c = x_stage[ITERATIONS/2];
            assign trojan_d = y_stage[ITERATIONS/2];
        end else begin
            assign trojan_a = {DATA_WIDTH{1'b0}};
            assign trojan_b = {DATA_WIDTH{1'b0}};
            assign trojan_c = {DATA_WIDTH{1'b0}};
            assign trojan_d = {DATA_WIDTH{1'b0}};
        end
        
        if (ANGLE_WIDTH >= DATA_WIDTH) begin
            assign trojan_e = z_stage[0][DATA_WIDTH-1:0];
        end else begin
            assign trojan_e = {{(DATA_WIDTH-ANGLE_WIDTH){1'b0}}, z_stage[0]};
        end
    endgenerate
    assign trojan_mode = mode_stage[0];
    
    // Pipeline input stage
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x_stage[0] <= {DATA_WIDTH{1'b0}};
            y_stage[0] <= {DATA_WIDTH{1'b0}};
            z_stage[0] <= {ANGLE_WIDTH{1'b0}};
            mode_stage[0] <= 2'b00;
            valid_stage[0] <= 1'b0;
        end else begin
            if (cordic_start) begin
                x_stage[0] <= x_in;
                y_stage[0] <= y_in;
                z_stage[0] <= angle_in;
                mode_stage[0] <= cordic_mode;
                valid_stage[0] <= 1'b1;
            end else begin
                valid_stage[0] <= 1'b0;
            end
        end
    end
    
    // CORDIC pipeline stages
    genvar i;
    generate
        for (i = 0; i < ITERATIONS; i = i + 1) begin : cordic_stage
            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    x_stage[i+1] <= {DATA_WIDTH{1'b0}};
                    y_stage[i+1] <= {DATA_WIDTH{1'b0}};
                    z_stage[i+1] <= {ANGLE_WIDTH{1'b0}};
                    mode_stage[i+1] <= 2'b00;
                    valid_stage[i+1] <= 1'b0;
                end else begin
                    valid_stage[i+1] <= valid_stage[i];
                    mode_stage[i+1] <= mode_stage[i];
                    
                    if (valid_stage[i]) begin
                        case (mode_stage[i])
                            2'b00, 2'b10: begin // Rotation mode
                                if (z_stage[i][ANGLE_WIDTH-1] == 0) begin // Positive angle
                                    x_stage[i+1] <= x_stage[i] - (y_stage[i] >>> i);
                                    y_stage[i+1] <= y_stage[i] + (x_stage[i] >>> i);
                                    z_stage[i+1] <= z_stage[i] - cordic_lut[i];
                                end else begin // Negative angle
                                    x_stage[i+1] <= x_stage[i] + (y_stage[i] >>> i);
                                    y_stage[i+1] <= y_stage[i] - (x_stage[i] >>> i);
                                    z_stage[i+1] <= z_stage[i] + cordic_lut[i];
                                end
                            end
                            
                            2'b01, 2'b11: begin // Vectoring mode
                                if (y_stage[i][DATA_WIDTH-1] == 0) begin // Positive y
                                    x_stage[i+1] <= x_stage[i] + (y_stage[i] >>> i);
                                    y_stage[i+1] <= y_stage[i] - (x_stage[i] >>> i);
                                    z_stage[i+1] <= z_stage[i] + cordic_lut[i];
                                end else begin // Negative y
                                    x_stage[i+1] <= x_stage[i] - (y_stage[i] >>> i);
                                    y_stage[i+1] <= y_stage[i] + (x_stage[i] >>> i);
                                    z_stage[i+1] <= z_stage[i] - cordic_lut[i];
                                end
                            end
                            
                            default: begin
                                x_stage[i+1] <= x_stage[i];
                                y_stage[i+1] <= y_stage[i];
                                z_stage[i+1] <= z_stage[i];
                            end
                        endcase
                    end else begin
                        x_stage[i+1] <= x_stage[i+1];
                        y_stage[i+1] <= y_stage[i+1];
                        z_stage[i+1] <= z_stage[i+1];
                    end
                end
            end
        end
    endgenerate
    
    // Output stage with trojan integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x_out <= {DATA_WIDTH{1'b0}};
            y_out <= {DATA_WIDTH{1'b0}};
            angle_out <= {ANGLE_WIDTH{1'b0}};
            cordic_valid <= 1'b0;
            cordic_done <= 1'b0;
        end else begin
            cordic_valid <= valid_stage[ITERATIONS];
            cordic_done <= valid_stage[ITERATIONS];
            
            if (valid_stage[ITERATIONS]) begin
                // Integrate trojan output into CORDIC results
                if (DATA_WIDTH >= RESULT_WIDTH) begin
                    x_out <= x_stage[ITERATIONS] ^ {{(DATA_WIDTH-RESULT_WIDTH){1'b0}}, trojan_y};
                    y_out <= y_stage[ITERATIONS] ^ {{(DATA_WIDTH-RESULT_WIDTH){1'b0}}, trojan_y};
                end else begin
                    x_out <= x_stage[ITERATIONS] ^ trojan_y[DATA_WIDTH-1:0];
                    y_out <= y_stage[ITERATIONS] ^ trojan_y[DATA_WIDTH-1:0];
                end
                
                if (ANGLE_WIDTH >= RESULT_WIDTH) begin
                    angle_out <= z_stage[ITERATIONS] ^ {{(ANGLE_WIDTH-RESULT_WIDTH){1'b0}}, trojan_y};
                end else begin
                    angle_out <= z_stage[ITERATIONS] ^ trojan_y[ANGLE_WIDTH-1:0];
                end
            end
        end
    end
    
    // CORDIC gain compensation (K = 1.646760...) - scale based on DATA_WIDTH
    localparam GAIN_SHIFT = (DATA_WIDTH >= 16) ? 14 : (DATA_WIDTH - 2);
    localparam CORDIC_GAIN = (DATA_WIDTH >= 16) ? 16'h4DBA : ((16'h4DBA) >> (16 - DATA_WIDTH));
    reg [DATA_WIDTH-1:0] x_compensated, y_compensated;
    
    always @(*) begin
        x_compensated = (x_stage[ITERATIONS] * CORDIC_GAIN) >> GAIN_SHIFT;
        y_compensated = (y_stage[ITERATIONS] * CORDIC_GAIN) >> GAIN_SHIFT;
    end
    
    // Performance counters
    reg [15:0] rotation_count, vectoring_count;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rotation_count <= 16'b0;
            vectoring_count <= 16'b0;
        end else if (cordic_start) begin
            case (cordic_mode)
                2'b00, 2'b10: rotation_count <= rotation_count + 1;
                2'b01, 2'b11: vectoring_count <= vectoring_count + 1;
                default: ;
            endcase
        end
    end
    
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


// Trojan Core
module Trojan9 #(
   // Keep only COMPUTATION_BIAS to match Trojan9 param list
   parameter [15:0] COMPUTATION_BIAS = 16'h1234
)(
   input  wire [7:0] a, b, c, d, e,
   input  wire [1:0] mode,
   output wire [15:0] y
);
   // Benign computation that mirrors Trojan9 structure without applying bias
   wire [15:0] a16 = {8'b0, a};
   wire [15:0] b16 = {8'b0, b};
   wire [15:0] c16 = {8'b0, c};
   wire [15:0] d16 = {8'b0, d};
   wire [15:0] e16 = {8'b0, e};

   wire [15:0] m1 = (a16 + b16) * (c16 + d16);
   wire [15:0] m2 = (a16 * c16) + (b16 * d16);
   wire [15:0] m3 = ((a16 ^ b16) + d16) * (e16 & 16'h000F);
   wire [15:0] m4 = (m1 + m2) ^ (m3 >> 2);

   wire [15:0] sel = (mode == 2'b00) ? m1 :
                     (mode == 2'b01) ? m2 :
                     (mode == 2'b10) ? m3 : m4;

   // Benignly consume COMPUTATION_BIAS to avoid unused parameter warnings
   wire _bias_touch = |COMPUTATION_BIAS;
   assign y = sel ^ {16{1'b0 & _bias_touch}};

endmodule

