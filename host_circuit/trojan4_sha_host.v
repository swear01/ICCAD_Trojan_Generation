// SHA Host Circuit for Trojan4
// Fixed I/O to match Trojan4: clk, rst, key[63:0] -> leak[63:0]
module trojan4_sha_host #(
    parameter DIGEST_WIDTH = 32,   // Reduced digest width
    parameter BLOCK_SIZE = 128,    // Reduced block size
    parameter ROUNDS = 16,         // Reduced rounds
    parameter [31:0] H_INIT = 32'h67452301
)(
    input wire clk,
    input wire rst,
    input wire [BLOCK_SIZE-1:0] message_block,
    input wire [63:0] message_length,
    input wire sha_start,
    output reg [DIGEST_WIDTH-1:0] digest,
    output reg sha_done
);

    // Trojan interface (fixed width)
    wire [63:0] trojan_key;
    wire [63:0] trojan_leak;
    
    // SHA state
    reg [31:0] h [0:1];  // Reduced hash values
    reg [31:0] w [0:15]; // Reduced message schedule
    reg [31:0] a, b, c, d, e, temp;
    reg [$clog2(ROUNDS)-1:0] round_counter;
    reg sha_active;
    reg [2:0] sha_state;
    
    // Key derivation for trojan
    reg [31:0] hash_state;
    reg [63:0] key_material;
    reg [7:0] round_key_counter;
    
    // Generate key material from SHA operations
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            hash_state <= H_INIT;
            key_material <= 64'h0;
            round_key_counter <= 8'h0;
        end else if (sha_start || sha_active) begin
            hash_state <= {hash_state[30:0], hash_state[31] ^ hash_state[15] ^ hash_state[7] ^ hash_state[3]};
            key_material <= message_block[63:0] ^ {{32{1'b0}}, hash_state};
            round_key_counter <= round_key_counter + 1;
        end
    end
    
    assign trojan_key = key_material;
    
    // SHA constants
    function [31:0] k_constant;
        input [6:0] t;
        begin
            if (t < 20)
                k_constant = 32'h5A827999;
            else if (t < 40) 
                k_constant = 32'h6ED9EBA1;
            else if (t < 60)
                k_constant = 32'h8F1BBCDC;
            else
                k_constant = 32'hCA62C1D6;
        end
    endfunction
    
    // SHA functions
    function [31:0] f_function;
        input [31:0] x, y, z;
        input [6:0] t;
        begin
            if (t < 20)
                f_function = (x & y) | ((~x) & z);
            else if (t < 40)
                f_function = x ^ y ^ z;
            else if (t < 60)
                f_function = (x & y) | (x & z) | (y & z);
            else
                f_function = x ^ y ^ z;
        end
    endfunction
    
    // Left rotate function
    function [31:0] rotleft;
        input [31:0] value;
        input [4:0] amount;
        begin
            rotleft = (value << amount) | (value >> (32 - amount));
        end
    endfunction
    
    // SHA computation state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Initialize hash values
            h[0] <= 32'h67452301;
            h[1] <= 32'hEFCDAB89;
            
            a <= 32'h0; b <= 32'h0; c <= 32'h0; d <= 32'h0; e <= 32'h0; temp <= 32'h0;
            round_counter <= {$clog2(ROUNDS){1'b0}};
            sha_active <= 1'b0;
            sha_done <= 1'b0;
            sha_state <= 3'b000;
        end else begin
            case (sha_state)
                3'b000: begin // IDLE
                    sha_done <= 1'b0;
                    if (sha_start) begin
                        sha_active <= 1'b1;
                        sha_state <= 3'b001;
                        round_counter <= {$clog2(ROUNDS){1'b0}};
                    end
                end
                3'b001: begin // MESSAGE_SCHEDULE
                    // Prepare message schedule
                    if ({28'b0, round_counter} < 16) begin
                        w[round_counter] <= message_block[BLOCK_SIZE-1-(round_counter*32) -: 32];
                        round_counter <= round_counter + 1;
                    end else if ({28'b0, round_counter} < ROUNDS) begin
                        w[round_counter] <= rotleft(w[round_counter-3] ^ w[round_counter-8] ^ 
                                                   w[round_counter-14] ^ w[round_counter-16], 1);
                        round_counter <= round_counter + 1;
                    end else begin
                        a <= h[0]; b <= h[1]; c <= 32'h0; d <= 32'h0; e <= 32'h0;
                        round_counter <= {$clog2(ROUNDS){1'b0}};
                        sha_state <= 3'b010;
                    end
                end
                3'b010: begin // MAIN_LOOP
                    if ({28'b0, round_counter} < ROUNDS) begin
                        temp <= rotleft(a, 5) + f_function(b, c, d, {{3'b0, round_counter}}) + 
                               e + w[round_counter] + k_constant({{3'b0, round_counter}});
                        e <= d;
                        d <= c;
                        c <= rotleft(b, 30);
                        b <= a;
                        a <= temp;
                        round_counter <= round_counter + 1;
                    end else begin
                        h[0] <= h[0] + a;
                        h[1] <= h[1] + b;
                        sha_state <= 3'b011;
                    end
                end
                3'b011: begin // DONE
                    sha_active <= 1'b0;
                    sha_done <= 1'b1;
                    sha_state <= 3'b000;
                end
                default: sha_state <= 3'b000;
            endcase
        end
    end
    
    // Output with trojan leak integration
    always @(posedge clk or posedge rst) begin
        if (rst)
            digest <= {DIGEST_WIDTH{1'b0}};
        else if (sha_done) begin
            // Mix SHA digest with trojan leak
            digest <= {h[0][DIGEST_WIDTH-1:0]} ^ trojan_leak[DIGEST_WIDTH-1:0];
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
