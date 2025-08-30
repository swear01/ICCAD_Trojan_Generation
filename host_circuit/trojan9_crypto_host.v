// Cryptographic Controller Host Circuit for Trojan9
// Interface: a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], mode[1:0] -> y[15:0]
module trojan9_crypto_host #(
    parameter CRYPTO_ROUNDS = 16,         // Number of encryption rounds
    parameter BLOCK_SIZE = 128,           // Block size in bits
    parameter [87:0] CRYPTO_PATTERN = 88'h123456789ABCDEF0123456  // Crypto data pattern
)(
    input wire clk,
    input wire rst,
    input wire [127:0] plaintext,
    input wire [127:0] key,
    input wire [1:0] crypto_mode,         // 0=AES, 1=DES, 2=custom, 3=test
    input wire encrypt_start,
    output reg [127:0] ciphertext,
    output reg encrypt_done
);

    // Trojan interface
    wire [7:0] trojan_a;
    wire [7:0] trojan_b;
    wire [7:0] trojan_c;
    wire [7:0] trojan_d;
    wire [7:0] trojan_e;
    wire [1:0] trojan_mode;
    wire [15:0] trojan_y;
    
    // Crypto components
    reg [127:0] state_reg;
    reg [127:0] key_schedule [0:15];      // Fixed to 16 round keys
    reg [87:0] crypto_gen;
    reg [4:0] round_counter;
    reg [2:0] crypto_state;
    reg [7:0] sbox_in, sbox_out;
    reg [7:0] sbox_output_temp;  // Temporary register to hold S-box output
    
    // S-box implementation (simplified)
    always @(*) begin
        case (sbox_in[3:0])
            4'h0: sbox_output_temp = 8'h63;
            4'h1: sbox_output_temp = 8'h7C;
            4'h2: sbox_output_temp = 8'h77;
            4'h3: sbox_output_temp = 8'h7B;
            4'h4: sbox_output_temp = 8'hF2;
            4'h5: sbox_output_temp = 8'h6B;
            4'h6: sbox_output_temp = 8'h6F;
            4'h7: sbox_output_temp = 8'hC5;
            4'h8: sbox_output_temp = 8'h30;
            4'h9: sbox_output_temp = 8'h01;
            4'hA: sbox_output_temp = 8'h67;
            4'hB: sbox_output_temp = 8'h2B;
            4'hC: sbox_output_temp = 8'hFE;
            4'hD: sbox_output_temp = 8'hD7;
            4'hE: sbox_output_temp = 8'hAB;
            4'hF: sbox_output_temp = 8'h76;
            default: sbox_output_temp = 8'h00;
        endcase
        // Apply Trojan influence to S-box output
        sbox_out = sbox_output_temp ^ {4'h0, sbox_in[7:4]} ^ trojan_y[7:0];
    end
    
    // Crypto controller state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            crypto_gen <= CRYPTO_PATTERN;
            crypto_state <= 3'h0;
            round_counter <= 5'h0;
            state_reg <= 128'h0;
            ciphertext <= 128'h0;
            encrypt_done <= 1'b0;
            
            // Initialize key schedule with better key derivation
            for (integer i = 0; i < 16; i = i + 1) begin
                key_schedule[i] = key ^ ({CRYPTO_PATTERN[31:0], CRYPTO_PATTERN[31:0], CRYPTO_PATTERN[31:0], CRYPTO_PATTERN[31:0]} >> (i*8));
            end
        end else begin
            crypto_gen <= {crypto_gen[86:0], crypto_gen[87]};
            
            case (crypto_state)
                3'h0: begin // IDLE
                    encrypt_done <= 1'b0;
                    if (encrypt_start) begin
                        state_reg <= plaintext ^ {112'h0, trojan_y[15:0]};  // Use 16-bit trojan output
                        round_counter <= 5'h0;
                        crypto_state <= 3'h1;
                    end
                end
                3'h1: begin // ADD_ROUND_KEY
                    if (round_counter < CRYPTO_ROUNDS) begin
                        state_reg <= state_reg ^ key_schedule[round_counter[3:0]];
                        crypto_state <= 3'h2;
                    end else begin
                        crypto_state <= 3'h5;  // FINAL_ROUND
                    end
                end
                3'h2: begin // SUB_BYTES
                    sbox_in <= state_reg[7:0];  // Process one byte at a time
                    crypto_state <= 3'h3;
                end
                3'h3: begin // SHIFT_ROWS (simplified)
                    // Use S-box output to update state register
                    state_reg <= {state_reg[127:8], sbox_out};
                    crypto_state <= 3'h4;
                end
                3'h4: begin // MIX_COLUMNS
                    case (crypto_mode)
                        2'b00: state_reg <= state_reg ^ {112'h0, trojan_y}; // AES-like
                        2'b01: state_reg <= {state_reg[126:0], state_reg[127]}; // DES-like rotation
                        2'b10: state_reg <= state_reg + {112'h0, trojan_y}; // Custom
                        2'b11: state_reg <= ~state_reg; // Test mode
                        default: state_reg <= state_reg;
                    endcase
                    round_counter <= round_counter + 1;
                    crypto_state <= 3'h1;  // Go back to ADD_ROUND_KEY for next round
                end
                3'h5: begin // FINAL_ROUND
                    // Use the last key schedule entry for final round
                    ciphertext <= state_reg ^ key_schedule[15];
                    encrypt_done <= 1'b1;
                    crypto_state <= 3'h0;
                end
                default: crypto_state <= 3'h0;
            endcase
        end
    end
    
    // Connect trojan inputs
    assign trojan_a = crypto_gen[7:0];
    assign trojan_b = state_reg[7:0];
    assign trojan_c = key[7:0];
    assign trojan_d = {3'h0, round_counter};
    assign trojan_e = {6'h0, crypto_mode};
    assign trojan_mode = crypto_state[1:0];
    
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
