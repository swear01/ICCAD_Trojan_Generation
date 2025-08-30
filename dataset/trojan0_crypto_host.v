// Crypto Host Circuit for Trojan0
// Fixed I/O to match Trojan0: key[127:0] -> load[63:0]
module trojan0_crypto_host #(
    parameter [127:0] KEY_INIT = 128'h0F1E2D3C4B5A69780F1E2D3C4B5A6978  // Crypto key seed
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] plaintext,
    input wire [DATA_WIDTH-1:0] cipher_key,
    input wire encrypt_start,
    output reg [DATA_WIDTH-1:0] ciphertext,
    output reg encrypt_done
);

    // Sizing parameters (converted from parameter to localparam)
    localparam DATA_WIDTH = 128;  // Cipher block size
    localparam ROUND_COUNT = 8;   // Number of encryption rounds

    // Trojan interface (fixed width)
    wire [127:0] trojan_key;
    wire [63:0] trojan_load;
    
    // Crypto state
    reg [DATA_WIDTH-1:0] state;
    reg [DATA_WIDTH-1:0] round_key;
    reg [127:0] key_generator;
    reg [3:0] round_counter;
    reg [2:0] crypto_state;
    reg state_at_finalize;  // Flag to indicate when we're at the finalize state
    
    // Key generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst)
            key_generator <= KEY_INIT;
        else if (encrypt_start || (crypto_state != 3'b000))
            key_generator <= {key_generator[119:0], key_generator[127:120] ^ cipher_key[7:0]};
    end
    
    assign trojan_key = key_generator;
    
    // Simple crypto state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= {DATA_WIDTH{1'b0}};
            round_key <= {DATA_WIDTH{1'b0}};
            round_counter <= 4'h0;
            crypto_state <= 3'b000;
            encrypt_done <= 1'b0;
            state_at_finalize <= 1'b0;
        end else begin
            case (crypto_state)
                3'b000: begin // IDLE
                    encrypt_done <= 1'b0;
                    state_at_finalize <= 1'b0;
                    if (encrypt_start) begin
                        state <= plaintext;
                        round_key <= cipher_key;
                        round_counter <= 4'h0;
                        crypto_state <= 3'b001;
                    end
                end
                3'b001: begin // ROUND_OPERATION
                    // Simple encryption round (XOR with rotated key)
                    state <= state ^ round_key;
                    round_key <= {round_key[126:0], round_key[127]};
                    
                    if (round_counter >= ROUND_COUNT-1) begin
                        crypto_state <= 3'b010;
                    end else begin
                        round_counter <= round_counter + 1;
                    end
                end
                3'b010: begin // FINALIZE
                    encrypt_done <= 1'b1;
                    state_at_finalize <= 1'b1;
                    crypto_state <= 3'b000;
                end
                default: crypto_state <= 3'b000;
            endcase
        end
    end
    
    // Output with trojan load integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ciphertext <= {DATA_WIDTH{1'b0}};
        end else if (state_at_finalize) begin
            // Mix ciphertext with trojan load
            ciphertext <= state ^ {{DATA_WIDTH-64{1'b0}}, trojan_load};
            state_at_finalize <= 1'b0;  // Clear the flag
        end
    end
    
    // Instantiate Trojan0
    Trojan0 trojan_inst (
        .clk(clk),
        .rst(rst),
        .key(trojan_key),
        .load(trojan_load)
    );

endmodule
