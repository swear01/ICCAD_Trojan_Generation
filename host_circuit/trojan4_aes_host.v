// AES Host Circuit for Trojan4
// Fixed I/O to match Trojan4: clk, rst, key[63:0] -> leak[63:0]
module trojan4_aes_host #(
    parameter KEY_SIZE = 64,      // Reduced AES key size
    parameter ROUNDS = 4,         // Reduced AES rounds
    parameter [255:0] SBOX_INIT = 256'hFEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210
)(
    input wire clk,
    input wire rst,
    input wire [127:0] plaintext_in,
    input wire [KEY_SIZE-1:0] aes_key,
    input wire aes_start,
    output reg [127:0] ciphertext_out,
    output reg aes_done
);

    // Trojan interface (fixed width)
    wire [63:0] trojan_key;
    wire [63:0] trojan_leak;
    
    // AES state
    reg [127:0] state_reg;
    reg [KEY_SIZE-1:0] round_keys [0:ROUNDS];
    reg [$clog2(ROUNDS+1)-1:0] round_counter;
    reg aes_active;
    
    // Key derivation for trojan
    reg [255:0] sbox_state;
    reg [63:0] derived_key;
    reg [7:0] key_schedule_counter;
    
    // Generate key material for trojan from AES operations
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sbox_state <= SBOX_INIT;
            derived_key <= 64'h0;
            key_schedule_counter <= 8'h0;
        end else if (aes_start || aes_active) begin
            sbox_state <= {sbox_state[254:0], sbox_state[255] ^ sbox_state[191] ^ sbox_state[127] ^ sbox_state[63]};
            derived_key <= {{(64-KEY_SIZE){1'b0}}, aes_key} ^ sbox_state[63:0];
            key_schedule_counter <= key_schedule_counter + 1;
        end
    end
    
    assign trojan_key = derived_key;
    
    // Key schedule generation (simplified)
    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i <= ROUNDS; i = i + 1) begin
                round_keys[i] <= {KEY_SIZE{1'b0}};
            end
        end else if (aes_start && !aes_active) begin
            round_keys[0] <= aes_key;
            for (i = 1; i <= ROUNDS; i = i + 1) begin
                // Simplified key schedule
                round_keys[i] <= round_keys[i-1] ^ {round_keys[i-1][KEY_SIZE-33:0], round_keys[i-1][KEY_SIZE-1:KEY_SIZE-32]};
            end
        end
    end
    
    // AES main state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state_reg <= 128'h0;
            round_counter <= {$clog2(ROUNDS+1){1'b0}};
            aes_active <= 1'b0;
            aes_done <= 1'b0;
        end else begin
            if (aes_start && !aes_active) begin
                state_reg <= plaintext_in ^ {{(128-KEY_SIZE){1'b0}}, round_keys[0]};
                round_counter <= {$clog2(ROUNDS+1){1'b0}};
                aes_active <= 1'b1;
                aes_done <= 1'b0;
            end else if (aes_active) begin
                if (round_counter < ROUNDS) begin
                    // Simplified AES round: SubBytes, ShiftRows, MixColumns, AddRoundKey
                    state_reg <= aes_round(state_reg, {{(128-KEY_SIZE){1'b0}}, round_keys[round_counter+1]});
                    round_counter <= round_counter + 1;
                end else begin
                    aes_active <= 1'b0;
                    aes_done <= 1'b1;
                end
            end else begin
                aes_done <= 1'b0;
            end
        end
    end
    
    // Simplified AES round function
    function [127:0] aes_round;
        input [127:0] state;
        input [127:0] round_key;
        begin
            // Simplified operations (SubBytes + ShiftRows + MixColumns combined)
            aes_round = {state[119:0], state[127:120]} ^ 
                       {state[111:8], state[7:0], state[127:112]} ^ 
                       round_key;
        end
    endfunction
    
    // Output with trojan leak integration
    always @(posedge clk or posedge rst) begin
        if (rst)
            ciphertext_out <= 128'h0;
        else if (aes_done) begin
            // Mix AES output with trojan leak
            ciphertext_out <= state_reg ^ {{64{1'b0}}, trojan_leak};
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
