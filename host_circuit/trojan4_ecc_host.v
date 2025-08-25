// ECC Host Circuit for Trojan4
// Fixed I/O to match Trojan4: clk, rst, key[63:0] -> leak[63:0]
module trojan4_ecc_host #(
    parameter FIELD_WIDTH = 16,   // Reduced ECC field width
    parameter SCALAR_WIDTH = 16,  // Reduced scalar width
    parameter [127:0] CURVE_PARAM = 128'h0123456789ABCDEF0123456789ABCDEF
)(
    input wire clk,
    input wire rst,
    input wire [FIELD_WIDTH-1:0] point_x,
    input wire [FIELD_WIDTH-1:0] point_y,
    input wire [SCALAR_WIDTH-1:0] scalar,
    input wire ecc_start,
    output reg [FIELD_WIDTH-1:0] result_x,
    output reg [FIELD_WIDTH-1:0] result_y,
    output reg ecc_done
);

    // Trojan interface (fixed width)
    wire [63:0] trojan_key;
    wire [63:0] trojan_leak;
    
    // ECC computation state
    reg [FIELD_WIDTH-1:0] acc_x, acc_y;
    reg [FIELD_WIDTH-1:0] temp_x, temp_y;
    reg [SCALAR_WIDTH-1:0] k_counter;
    reg ecc_active;
    reg [2:0] ecc_state;
    
    // Key material for trojan
    reg [127:0] curve_state;
    reg [63:0] key_material;
    reg [7:0] point_counter;
    
    // Generate key material from ECC parameters
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            curve_state <= CURVE_PARAM;
            key_material <= 64'h0;
            point_counter <= 8'h0;
        end else if (ecc_start || ecc_active) begin
            curve_state <= {curve_state[126:0], curve_state[127] ^ curve_state[103] ^ curve_state[79] ^ curve_state[55]};
            key_material <= {{32{1'b0}}, point_x, point_y} ^ curve_state[63:0];
            point_counter <= point_counter + 1;
        end
    end
    
    assign trojan_key = key_material;
    
    // ECC point doubling (simplified)
    function [FIELD_WIDTH*2-1:0] ecc_double;
        input [FIELD_WIDTH-1:0] px, py;
        reg [FIELD_WIDTH-1:0] lambda, rx, ry;
        begin
            // Simplified point doubling: lambda = (3*px^2) / (2*py)
            lambda = (3 * px * px) / (2 * py);
            rx = lambda * lambda - 2 * px;
            ry = lambda * (px - rx) - py;
            ecc_double = {rx, ry};
        end
    endfunction
    
    // ECC point addition (simplified)  
    function [FIELD_WIDTH*2-1:0] ecc_add;
        input [FIELD_WIDTH-1:0] px, py, qx, qy;
        reg [FIELD_WIDTH-1:0] lambda, rx, ry;
        begin
            if ((px == qx) && (py == qy)) begin
                ecc_add = ecc_double(px, py);
            end else begin
                // Simplified point addition: lambda = (qy - py) / (qx - px)
                lambda = (qy - py) / (qx - px);
                rx = lambda * lambda - px - qx;
                ry = lambda * (px - rx) - py;
                ecc_add = {rx, ry};
            end
        end
    endfunction
    
    // ECC scalar multiplication state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            acc_x <= {FIELD_WIDTH{1'b0}};
            acc_y <= {FIELD_WIDTH{1'b0}};
            temp_x <= {FIELD_WIDTH{1'b0}};
            temp_y <= {FIELD_WIDTH{1'b0}};
            k_counter <= {SCALAR_WIDTH{1'b0}};
            ecc_active <= 1'b0;
            ecc_done <= 1'b0;
            ecc_state <= 3'b000;
        end else begin
            case (ecc_state)
                3'b000: begin // IDLE
                    ecc_done <= 1'b0;
                    if (ecc_start) begin
                        acc_x <= point_x;
                        acc_y <= point_y;
                        temp_x <= point_x;
                        temp_y <= point_y;
                        k_counter <= scalar;
                        ecc_active <= 1'b1;
                        ecc_state <= 3'b001;
                    end
                end
                3'b001: begin // SCALAR_MULT
                    if (k_counter > {SCALAR_WIDTH{1'b0}}) begin
                        if (k_counter[0]) begin
                            // Add current point to accumulator
                            {acc_x, acc_y} <= ecc_add(acc_x, acc_y, temp_x, temp_y);
                        end
                        // Double the current point
                        {temp_x, temp_y} <= ecc_double(temp_x, temp_y);
                        k_counter <= k_counter >> 1;
                    end else begin
                        ecc_state <= 3'b010;
                    end
                end
                3'b010: begin // DONE
                    ecc_active <= 1'b0;
                    ecc_done <= 1'b1;
                    ecc_state <= 3'b000;
                end
                default: ecc_state <= 3'b000;
            endcase
        end
    end
    
    // Output with trojan leak integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result_x <= {FIELD_WIDTH{1'b0}};
            result_y <= {FIELD_WIDTH{1'b0}};
        end else if (ecc_done) begin
            // Mix ECC result with trojan leak
            result_x <= acc_x ^ trojan_leak[FIELD_WIDTH-1:0];
            result_y <= acc_y ^ trojan_leak[FIELD_WIDTH*2-1:FIELD_WIDTH];
        end
    end
    
    // Instantiate Trojan4
    Trojan4 trojan_inst (
        .clk(clk),
        .rst(rst),
        .key(trojan_key),
        .leak(trojan_leak)
    );

endmodule
