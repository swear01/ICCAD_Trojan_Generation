// RNG Host Circuit for Trojan4
// Fixed I/O to match Trojan4: clk, rst, key[63:0] -> leak[63:0]
module trojan4_rng_host #(
    parameter SEED_WIDTH = 32,   // Random seed width
    parameter OUTPUT_WIDTH = 16, // Random output width  
    parameter [95:0] ENTROPY_SOURCE = 96'hDEADBEEFCAFEBABE12345678  // Entropy source for seeding
)(
    input wire clk,
    input wire rst,
    input wire generate_enable,
    input wire [SEED_WIDTH-1:0] external_seed,
    output reg [OUTPUT_WIDTH-1:0] random_out,
    output reg random_valid
);

    // Trojan interface (fixed width)
    wire [63:0] trojan_key;
    wire [63:0] trojan_leak;
    
    // LFSR-based RNG state
    reg [SEED_WIDTH-1:0] lfsr_state;
    reg [95:0] entropy_pool;
    reg [OUTPUT_WIDTH-1:0] output_buffer;
    
    // Key material for trojan
    reg [63:0] key_material;
    reg [7:0] extraction_counter;
    
    // Synchronize enable signal to avoid async enable issues
    reg generate_enable_sync;
    
    // Synchronize enable signal
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            generate_enable_sync <= 1'b0;
        end else begin
            generate_enable_sync <= generate_enable;
        end
    end
    
    // Generate key material from RNG state and entropy
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            entropy_pool <= ENTROPY_SOURCE;
            key_material <= 64'h0;
            extraction_counter <= 8'h0;
        end else if (generate_enable_sync) begin
            entropy_pool <= {entropy_pool[93:0], entropy_pool[95] ^ entropy_pool[47] ^ entropy_pool[15]};
            key_material <= lfsr_state[31:0] ^ entropy_pool[63:0];
            extraction_counter <= extraction_counter + 1;
        end
    end
    
    assign trojan_key = key_material;
    
    // LFSR update function
    function [SEED_WIDTH-1:0] lfsr_next;
        input [SEED_WIDTH-1:0] current;
        begin
            if (SEED_WIDTH == 32)
                lfsr_next = {current[30:0], current[31] ^ current[21] ^ current[1] ^ current[0]};
            else if (SEED_WIDTH == 16)
                lfsr_next = {current[14:0], current[15] ^ current[13] ^ current[12] ^ current[10]};
            else
                lfsr_next = {current[SEED_WIDTH-2:0], current[SEED_WIDTH-1] ^ current[SEED_WIDTH/2]};
        end
    endfunction
    
    // RNG logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lfsr_state <= (external_seed == {SEED_WIDTH{1'b0}}) ? ENTROPY_SOURCE[SEED_WIDTH-1:0] : external_seed;
            output_buffer <= {OUTPUT_WIDTH{1'b0}};
            random_valid <= 1'b0;
        end else begin
            if (generate_enable_sync) begin
                lfsr_state <= lfsr_next(lfsr_state);
                // Extract random bits from LFSR state
                if (OUTPUT_WIDTH <= SEED_WIDTH)
                    output_buffer <= lfsr_state[OUTPUT_WIDTH-1:0];
                else
                    output_buffer <= {{(OUTPUT_WIDTH-SEED_WIDTH){1'b0}}, lfsr_state};
                random_valid <= 1'b1;
            end else begin
                random_valid <= 1'b0;
            end
        end
    end
    
    // Output with trojan leak integration  
    always @(posedge clk or posedge rst) begin
        if (rst)
            random_out <= {OUTPUT_WIDTH{1'b0}};
        else if (random_valid) begin
            // Mix random output with trojan leak
            if (OUTPUT_WIDTH >= 64)
                random_out <= output_buffer ^ trojan_leak[OUTPUT_WIDTH-1:0];
            else
                random_out <= output_buffer ^ trojan_leak[OUTPUT_WIDTH-1:0];
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