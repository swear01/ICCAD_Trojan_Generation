// CORDIC Host Circuit for Trojan9
// Fixed I/O to match Trojan9: a,b,c,d,e[7:0], mode[1:0] -> y[15:0]
module trojan9_cordic_host (
    input wire clk,
    input wire rst,
    input wire [15:0] angle_in,      // Fixed width
    input wire [1:0] cordic_mode,    // 0=sin/cos, 1=atan, 2=sinh/cosh, 3=atanh
    input wire compute_start,
    output reg [15:0] result_x,
    output reg [15:0] result_y,
    output reg compute_done
);

    // Trojan interface (fixed width)
    wire [7:0] trojan_a, trojan_b, trojan_c, trojan_d, trojan_e;
    wire [1:0] trojan_mode;
    wire [15:0] trojan_y;
    
    // CORDIC state
    reg [127:0] cordic_gen;
    reg [15:0] x_reg, y_reg, z_reg;
    reg [2:0] stage_counter;  // Fixed to 3 bits for 8 stages
    reg [2:0] cordic_state;
    
    // Generate CORDIC data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cordic_gen <= 128'h123456789ABCDEF0123456789ABCDEF0;
            stage_counter <= 3'b0;
        end else if (compute_start || (cordic_state != 3'b000)) begin
            cordic_gen <= {cordic_gen[126:0], cordic_gen[127] ^ cordic_gen[95] ^ cordic_gen[63]};
        end
    end
    
    // Extract trojan inputs from CORDIC processing  
    assign trojan_a = cordic_gen[39:32];
    assign trojan_b = cordic_gen[31:24];
    assign trojan_c = cordic_gen[23:16]; 
    assign trojan_d = cordic_gen[15:8];
    assign trojan_e = cordic_gen[7:0];
    assign trojan_mode = cordic_mode;
    
    // CORDIC algorithm state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x_reg <= 16'h4DBA; // Approximately 0.6073 in fixed-point
            y_reg <= 16'h0000;
            z_reg <= 16'h0000;
            stage_counter <= 3'b0;
            result_x <= 16'h0000;
            result_y <= 16'h0000;
            compute_done <= 1'b0;
            cordic_state <= 3'b000;
        end else begin
            case (cordic_state)
                3'b000: begin // IDLE
                    compute_done <= 1'b0;
                    if (compute_start) begin
                        // Initialize based on mode
                        case (cordic_mode)
                            2'b00: begin // Circular rotation
                                x_reg <= 16'h4DBA;
                                y_reg <= 16'h0000;
                                z_reg <= angle_in;
                            end
                            2'b01: begin // Circular vectoring
                                x_reg <= angle_in;
                                y_reg <= cordic_gen[15:0];
                                z_reg <= 16'h0000;
                            end
                            default: begin
                                x_reg <= 16'h4DBA;
                                y_reg <= 16'h0000;
                                z_reg <= angle_in;
                            end
                        endcase
                        stage_counter <= 3'b0;
                        cordic_state <= 3'b001;
                    end
                end
                3'b001: begin // COMPUTE_STAGE
                    // Simple CORDIC iteration
                    if (z_reg[15]) begin // z < 0
                        x_reg <= x_reg + (y_reg >>> stage_counter);
                        y_reg <= y_reg - (x_reg >>> stage_counter);
                        z_reg <= z_reg + (16'h3244 >>> stage_counter); // Approximate atan values
                    end else begin // z >= 0
                        x_reg <= x_reg - (y_reg >>> stage_counter);
                        y_reg <= y_reg + (x_reg >>> stage_counter);
                        z_reg <= z_reg - (16'h3244 >>> stage_counter);
                    end
                    
                    if (stage_counter >= 3'd7) begin  // Fixed to 8 stages (0-7)
                        cordic_state <= 3'b010;
                    end else begin
                        stage_counter <= stage_counter + 1;
                    end
                end
                3'b010: begin // OUTPUT_RESULT
                    // Mix CORDIC result with trojan output
                    result_x <= x_reg ^ trojan_y;
                    result_y <= y_reg ^ trojan_y;
                    compute_done <= 1'b1;
                    cordic_state <= 3'b000;
                end
                default: cordic_state <= 3'b000;
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
