// Pipelined CORDIC Host Circuit for Trojan9
// Interface: a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], mode[1:0] -> y[15:0]
module trojan9_cordic_host #(
    parameter DATA_WIDTH = 16,
    parameter ANGLE_WIDTH = 16,
    parameter ITERATIONS = 8
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
    wire [7:0] trojan_a, trojan_b, trojan_c, trojan_d, trojan_e,
    wire [1:0] trojan_mode,
    wire [15:0] trojan_y
);

    // CORDIC pipeline stages
    reg [DATA_WIDTH-1:0] x_stage [ITERATIONS:0];
    reg [DATA_WIDTH-1:0] y_stage [ITERATIONS:0];
    reg [ANGLE_WIDTH-1:0] z_stage [ITERATIONS:0];
    reg [1:0] mode_stage [ITERATIONS:0];
    reg valid_stage [ITERATIONS:0];
    
    // CORDIC LUT for angles
    reg [ANGLE_WIDTH-1:0] cordic_lut [ITERATIONS-1:0];
    initial begin
        cordic_lut[0] = 16'h2000; // atan(2^-0) * 2^14
        cordic_lut[1] = 16'h12E4; // atan(2^-1) * 2^14
        cordic_lut[2] = 16'h09FB; // atan(2^-2) * 2^14
        cordic_lut[3] = 16'h0511; // atan(2^-3) * 2^14
        cordic_lut[4] = 16'h028B; // atan(2^-4) * 2^14
        cordic_lut[5] = 16'h0146; // atan(2^-5) * 2^14
        cordic_lut[6] = 16'h00A3; // atan(2^-6) * 2^14
        cordic_lut[7] = 16'h0051; // atan(2^-7) * 2^14
    end
    
    // Generate trojan signals from CORDIC operations
    assign trojan_a = x_stage[0][7:0];
    assign trojan_b = y_stage[0][7:0];
    assign trojan_c = x_stage[ITERATIONS/2][7:0];
    assign trojan_d = y_stage[ITERATIONS/2][7:0];
    assign trojan_e = z_stage[0][7:0];
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
                if (DATA_WIDTH >= 16) begin
                    x_out <= x_stage[ITERATIONS] ^ {{(DATA_WIDTH-16){1'b0}}, trojan_y};
                    y_out <= y_stage[ITERATIONS] ^ {{(DATA_WIDTH-16){1'b0}}, trojan_y};
                end else begin
                    x_out <= x_stage[ITERATIONS] ^ trojan_y[DATA_WIDTH-1:0];
                    y_out <= y_stage[ITERATIONS] ^ trojan_y[DATA_WIDTH-1:0];
                end
                
                if (ANGLE_WIDTH >= 16) begin
                    angle_out <= z_stage[ITERATIONS] ^ {{(ANGLE_WIDTH-16){1'b0}}, trojan_y};
                end else begin
                    angle_out <= z_stage[ITERATIONS] ^ trojan_y[ANGLE_WIDTH-1:0];
                end
            end
        end
    end
    
    // CORDIC gain compensation (K = 1.646760...)
    parameter CORDIC_GAIN = 16'h4DBA; // 1.646760 * 2^14
    reg [DATA_WIDTH-1:0] x_compensated, y_compensated;
    
    always @(*) begin
        x_compensated = (x_stage[ITERATIONS] * CORDIC_GAIN) >> 14;
        y_compensated = (y_stage[ITERATIONS] * CORDIC_GAIN) >> 14;
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