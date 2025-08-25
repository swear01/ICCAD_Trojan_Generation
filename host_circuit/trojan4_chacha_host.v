// ChaCha Host Circuit for Trojan4
// Fixed I/O to match Trojan4: clk, rst, key[63:0] -> leak[63:0]
module trojan4_chacha_host #(
    parameter ROUNDS = 8,         // Reduced ChaCha rounds
    parameter BLOCK_SIZE = 256,   // Reduced block size
    parameter [511:0] CONSTANT_INIT = 512'h61707865_3320646E_79622D32_6B206574_000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
)(
    input wire clk,
    input wire rst,
    input wire [255:0] chacha_key,
    input wire [95:0] nonce,
    input wire [31:0] counter,
    input wire chacha_start,
    output reg [BLOCK_SIZE-1:0] keystream,
    output reg chacha_done
);

    // Trojan interface (fixed width)
    wire [63:0] trojan_key;
    wire [63:0] trojan_leak;
    
    // ChaCha state
    reg [31:0] state [0:15];  // ChaCha 4x4 state matrix
    reg [31:0] working_state [0:15];
    reg [$clog2(ROUNDS/2)-1:0] round_counter;
    reg chacha_active;
    reg [2:0] chacha_state;
    
    // Key derivation for trojan
    reg [511:0] constant_state;
    reg [63:0] key_material;
    reg [7:0] quarter_round_counter;
    
    // Generate key material from ChaCha operations
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            constant_state <= CONSTANT_INIT;
            key_material <= 64'h0;
            quarter_round_counter <= 8'h0;
        end else if (chacha_start || chacha_active) begin
            constant_state <= {constant_state[510:0], constant_state[511] ^ constant_state[383] ^ constant_state[255] ^ constant_state[127]};
            key_material <= chacha_key[63:0] ^ constant_state[63:0];
            quarter_round_counter <= quarter_round_counter + 1;
        end
    end
    
    assign trojan_key = key_material;
    
    // ChaCha quarter round function
    task quarter_round;
        inout [31:0] a, b, c, d;
        begin
            a = a + b; d = d ^ a; d = {d[15:0], d[31:16]}; // ROL 16
            c = c + d; b = b ^ c; b = {b[19:0], b[31:20]}; // ROL 12
            a = a + b; d = d ^ a; d = {d[23:0], d[31:24]}; // ROL 8
            c = c + d; b = b ^ c; b = {b[24:0], b[31:25]}; // ROL 7
        end
    endtask
    
    // ChaCha computation state machine
    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Initialize state
            for (i = 0; i < 16; i = i + 1) begin
                state[i] <= 32'h0;
                working_state[i] <= 32'h0;
            end
            round_counter <= {$clog2(ROUNDS/2){1'b0}};
            chacha_active <= 1'b0;
            chacha_done <= 1'b0;
            chacha_state <= 3'b000;
        end else begin
            case (chacha_state)
                3'b000: begin // IDLE
                    chacha_done <= 1'b0;
                    if (chacha_start) begin
                        // Initialize ChaCha state
                        // Constants
                        state[0] <= 32'h61707865;
                        state[1] <= 32'h3320646e;
                        state[2] <= 32'h79622d32;
                        state[3] <= 32'h6b206574;
                        // Key
                        state[4] <= chacha_key[31:0];
                        state[5] <= chacha_key[63:32];
                        state[6] <= chacha_key[95:64];
                        state[7] <= chacha_key[127:96];
                        state[8] <= chacha_key[159:128];
                        state[9] <= chacha_key[191:160];
                        state[10] <= chacha_key[223:192];
                        state[11] <= chacha_key[255:224];
                        // Counter
                        state[12] <= counter;
                        // Nonce
                        state[13] <= nonce[31:0];
                        state[14] <= nonce[63:32];
                        state[15] <= nonce[95:64];
                        
                        // Copy to working state
                        for (i = 0; i < 16; i = i + 1) begin
                            working_state[i] <= state[i];
                        end
                        
                        chacha_active <= 1'b1;
                        chacha_state <= 3'b001;
                        round_counter <= {$clog2(ROUNDS/2){1'b0}};
                    end
                end
                3'b001: begin // ROUNDS
                    if ({28'b0, round_counter} < ROUNDS/2) begin
                        // Column rounds
                        quarter_round(working_state[0], working_state[4], working_state[8], working_state[12]);
                        quarter_round(working_state[1], working_state[5], working_state[9], working_state[13]);
                        quarter_round(working_state[2], working_state[6], working_state[10], working_state[14]);
                        quarter_round(working_state[3], working_state[7], working_state[11], working_state[15]);
                        
                        // Diagonal rounds
                        quarter_round(working_state[0], working_state[5], working_state[10], working_state[15]);
                        quarter_round(working_state[1], working_state[6], working_state[11], working_state[12]);
                        quarter_round(working_state[2], working_state[7], working_state[8], working_state[13]);
                        quarter_round(working_state[3], working_state[4], working_state[9], working_state[14]);
                        
                        round_counter <= round_counter + 1;
                    end else begin
                        chacha_state <= 3'b010;
                    end
                end
                3'b010: begin // FINALIZE
                    // Add original state to working state
                    for (i = 0; i < 16; i = i + 1) begin
                        working_state[i] <= working_state[i] + state[i];
                    end
                    chacha_state <= 3'b011;
                end
                3'b011: begin // DONE
                    chacha_active <= 1'b0;
                    chacha_done <= 1'b1;
                    chacha_state <= 3'b000;
                end
                default: chacha_state <= 3'b000;
            endcase
        end
    end
    
    // Output with trojan leak integration
    always @(posedge clk or posedge rst) begin
        if (rst)
            keystream <= {BLOCK_SIZE{1'b0}};
        else if (chacha_done) begin
            // Mix ChaCha keystream with trojan leak
            keystream <= {working_state[0], working_state[1], working_state[2], working_state[3],
                         working_state[4], working_state[5], working_state[6], working_state[7]} ^
                        {{(BLOCK_SIZE-64){1'b0}}, trojan_leak};
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
