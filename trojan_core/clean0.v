module Trojan0 #(
    // Match Trojan0: keep only non-I/O parameter
    parameter [63:0] LOAD_XOR_MASK = 64'h8FADC1A6B5E37921
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [127:0] key,
    output reg  [63:0] load
);
    // Clean implementation - pass-through, but use LOAD_XOR_MASK and reference upper key bits in a no-op way
    always @(posedge clk) begin
        if (rst) begin
            load <= 64'b0;
        end else begin
            // Use mask twice (cancels) and also read key[127:64] in a no-op term to avoid unused-bit warnings
            load <= ((key[63:0] ^ LOAD_XOR_MASK) ^ LOAD_XOR_MASK) ^ (({64{^key[127:64]}}) & 64'b0);
        end
    end

endmodule


// No auxiliary submodules in clean version
