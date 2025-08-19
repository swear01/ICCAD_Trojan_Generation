// Decoder Host Circuit for Trojan5
// Fixed I/O to match Trojan5: pon_rst_n_i, prog_dat_i[13:0], pc_reg[12:0] -> prog_adr_o[12:0]
module trojan5_decoder_host #(
    parameter DECODE_WIDTH = 8,  // Decoder input width
    parameter OUTPUT_COUNT = 16, // Number of decoded outputs
    parameter [127:0] DECODE_PATTERN = 128'hFEDCBA9876543210FEDCBA9876543210  // Pattern for decode data
)(
    input wire clk,
    input wire pon_rst_n_i,
    input wire [DECODE_WIDTH-1:0] encoded_input,
    input wire decode_enable,
    output reg [OUTPUT_COUNT-1:0] decoded_output,
    output reg decode_valid
);

    // Trojan interface (fixed width)
    wire [13:0] trojan_prog_dat_i;
    wire [12:0] trojan_pc_reg;
    wire [12:0] trojan_prog_adr_o;
    
    // Decoder state
    reg [127:0] pattern_gen;
    reg [12:0] address_counter;
    reg [3:0] decode_state;
    
    // Generate program data for trojan from decoder input
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            pattern_gen <= DECODE_PATTERN;
            address_counter <= 13'h0;
        end else if (decode_enable) begin
            pattern_gen <= {pattern_gen[125:0], pattern_gen[127] ^ pattern_gen[95] ^ encoded_input[0]};
            address_counter <= address_counter + 1;
        end
    end
    
    assign trojan_prog_dat_i = pattern_gen[13:0];
    assign trojan_pc_reg = address_counter;
    
    // Decoder logic
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            decoded_output <= {OUTPUT_COUNT{1'b0}};
            decode_valid <= 1'b0;
            decode_state <= 4'h0;
        end else begin
            if (decode_enable) begin
                case (decode_state)
                    4'h0: begin // Start decode
                        decoded_output <= {OUTPUT_COUNT{1'b0}};
                        decode_state <= 4'h1;
                        decode_valid <= 1'b0;
                    end
                    4'h1: begin // Decode process
                        // Simple binary decode
                        if (encoded_input < OUTPUT_COUNT)
                            decoded_output[encoded_input] <= 1'b1;
                        decode_state <= 4'h2;
                    end
                    4'h2: begin // Output ready
                        decode_valid <= 1'b1;
                        decode_state <= 4'h3;
                    end
                    4'h3: begin // Wait
                        decode_valid <= 1'b0;
                        decode_state <= 4'h0;
                    end
                    default: begin
                        decode_state <= 4'h0;
                    end
                endcase
            end else begin
                decode_valid <= 1'b0;
            end
        end
    end
    
    // Instantiate Trojan5
    Trojan5 trojan_inst (
        .pon_rst_n_i(pon_rst_n_i),
        .prog_dat_i(trojan_prog_dat_i),
        .pc_reg(trojan_pc_reg),
        .prog_adr_o(trojan_prog_adr_o)
    );

endmodule