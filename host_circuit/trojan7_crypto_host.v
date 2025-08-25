// Crypto Host Circuit for Trojan7
// Fixed I/O to match Trojan7: wb_addr_i[31:0], wb_data_i[31:0], s0_data_i[31:0] -> slv_sel[3:0]
module trojan7_crypto_host #(
    parameter KEY_ROUNDS = 10,        // Number of encryption rounds
    parameter SBOX_SIZE = 256,        // S-box size
    parameter [255:0] CRYPTO_PATTERN = 256'hDEADBEEFCAFEBABE0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF  // Crypto data pattern
)(
    input wire clk,
    input wire rst,
    input wire [127:0] plaintext,
    input wire [127:0] key,
    input wire encrypt_start,
    input wire decrypt_start,
    output reg [127:0] ciphertext,
    output reg crypto_done
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_wb_addr_i;
    wire [31:0] trojan_wb_data_i;
    wire [31:0] trojan_s0_data_i;
    wire [3:0] trojan_slv_sel;
    
    // Crypto state - fixed constants
    localparam STATE_SIZE = 16;
    localparam KEY_SIZE = 16;
    
    reg [7:0] sbox [0:255];           // Fixed S-box size
    reg [7:0] state [0:15];           // Fixed state size
    reg [7:0] round_keys [0:15];      // Fixed round key size
    reg [255:0] crypto_gen;
    reg [4:0] crypto_state;
    reg [3:0] current_round;
    reg [7:0] temp_byte;
    
    // Loop variables
    integer i, j;
    
    // Initialize S-box with pattern
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            crypto_gen <= CRYPTO_PATTERN;
            // Initialize S-box using blocking assignment
            for (i = 0; i < 256; i = i + 1) begin
                sbox[i] = CRYPTO_PATTERN[7:0] + i[7:0];
            end
            // Initialize state
            for (i = 0; i < 16; i = i + 1) begin
                state[i] <= 8'h0;
                round_keys[i] <= 8'h0;
            end
        end else if (encrypt_start || decrypt_start) begin
            crypto_gen <= {crypto_gen[254:0], crypto_gen[255] ^ crypto_gen[223] ^ crypto_gen[191] ^ crypto_gen[159]};
        end
    end
    
    assign trojan_wb_addr_i = {24'h0, state[4]};
    assign trojan_wb_data_i = crypto_gen[31:0];
    assign trojan_s0_data_i = {state[3], state[2], state[1], state[0]};
    
    // Crypto processing logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ciphertext <= 128'h0;
            crypto_done <= 1'b0;
            crypto_state <= 5'h0;
            current_round <= 4'h0;
            temp_byte <= 8'h0;
        end else begin
            case (crypto_state)
                5'h0: begin // IDLE
                    crypto_done <= 1'b0;
                    if (encrypt_start) begin
                        // Load plaintext into state
                        state[0] <= plaintext[7:0];   state[1] <= plaintext[15:8];
                        state[2] <= plaintext[23:16]; state[3] <= plaintext[31:24];
                        state[4] <= plaintext[39:32]; state[5] <= plaintext[47:40];
                        state[6] <= plaintext[55:48]; state[7] <= plaintext[63:56];
                        state[8] <= plaintext[71:64]; state[9] <= plaintext[79:72];
                        state[10] <= plaintext[87:80]; state[11] <= plaintext[95:88];
                        state[12] <= plaintext[103:96]; state[13] <= plaintext[111:104];
                        state[14] <= plaintext[119:112]; state[15] <= plaintext[127:120];
                        // Generate round keys from key
                        round_keys[0] <= key[7:0];   round_keys[1] <= key[15:8];
                        round_keys[2] <= key[23:16]; round_keys[3] <= key[31:24];
                        round_keys[4] <= key[39:32]; round_keys[5] <= key[47:40];
                        round_keys[6] <= key[55:48]; round_keys[7] <= key[63:56];
                        round_keys[8] <= key[71:64]; round_keys[9] <= key[79:72];
                        round_keys[10] <= key[87:80]; round_keys[11] <= key[95:88];
                        round_keys[12] <= key[103:96]; round_keys[13] <= key[111:104];
                        round_keys[14] <= key[119:112]; round_keys[15] <= key[127:120];
                        current_round <= 4'h0;
                        crypto_state <= 5'h1;
                    end else if (decrypt_start) begin
                        // Load ciphertext into state
                        state[0] <= plaintext[7:0];   state[1] <= plaintext[15:8];
                        state[2] <= plaintext[23:16]; state[3] <= plaintext[31:24];
                        state[4] <= plaintext[39:32]; state[5] <= plaintext[47:40];
                        state[6] <= plaintext[55:48]; state[7] <= plaintext[63:56];
                        state[8] <= plaintext[71:64]; state[9] <= plaintext[79:72];
                        state[10] <= plaintext[87:80]; state[11] <= plaintext[95:88];
                        state[12] <= plaintext[103:96]; state[13] <= plaintext[111:104];
                        state[14] <= plaintext[119:112]; state[15] <= plaintext[127:120];
                        current_round <= KEY_ROUNDS;
                        crypto_state <= 5'h2;
                    end
                end
                5'h1: begin // ENCRYPT_ROUND
                    if (current_round < KEY_ROUNDS) begin
                        // SubBytes transformation
                        for (i = 0; i < 16; i = i + 1) begin
                            state[i] <= sbox[state[i]];
                        end
                        // ShiftRows (simplified)
                        temp_byte <= state[1];
                        state[1] <= state[5];
                        state[5] <= state[9];
                        state[9] <= state[13];
                        state[13] <= temp_byte;
                        // AddRoundKey
                        for (i = 0; i < 16; i = i + 1) begin
                            state[i] <= state[i] ^ round_keys[i];
                        end
                        current_round <= current_round + 1;
                    end else begin
                        crypto_state <= 5'h3;
                    end
                end
                5'h2: begin // DECRYPT_ROUND
                    if (current_round > 0) begin
                        // Inverse operations (simplified)
                        for (i = 0; i < 16; i = i + 1) begin
                            state[i] <= state[i] ^ round_keys[i];
                        end
                        current_round <= current_round - 1;
                    end else begin
                        crypto_state <= 5'h3;
                    end
                end
                5'h3: begin // OUTPUT
                    // Apply trojan payload to output
                    ciphertext <= {state[15], state[14], state[13], state[12],
                                  state[11], state[10], state[9], state[8],
                                  state[7], state[6], state[5], state[4],
                                  state[3] ^ {4'h0, trojan_slv_sel}, state[2], state[1], state[0]};
                    crypto_done <= 1'b1;
                    crypto_state <= 5'h0;
                end
                default: crypto_state <= 5'h0;
            endcase
        end
    end
    
    // Instantiate Trojan7
    Trojan7 trojan_inst (
        .wb_addr_i(trojan_wb_addr_i),
        .wb_data_i(trojan_wb_data_i),
        .s0_data_i(trojan_s0_data_i),
        .slv_sel(trojan_slv_sel)
    );

endmodule
