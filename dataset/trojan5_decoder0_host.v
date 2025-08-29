// Decoder Host Circuit for Trojan5
module trojan5_decoder0_host #(
    parameter DECODE_PATTERN = 128'hFEDCBA9876543210FEDCBA9876543210
)(
    input wire clk,
    input wire pon_rst_n_i,
    input wire [7:0] encoded_input,  // Fixed width
    input wire decode_enable,
    output reg [15:0] decoded_output, // Fixed width
    output reg decode_valid,
    output reg [12:0] prog_adr_out    // Connect trojan address output
);

    // Trojan interface (fixed width)
    wire [13:0] trojan_prog_dat_i;
    wire [12:0] trojan_pc_reg;
    wire [12:0] trojan_prog_adr_o;
    
    reg [127:0] pattern_gen;
    reg [12:0] address_counter;
    reg [3:0] decode_state;
    
    assign trojan_prog_dat_i = pattern_gen[13:0];
    assign trojan_pc_reg = address_counter;
    
    // Generate program data for trojan from decoder input
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            pattern_gen <= DECODE_PATTERN;
        end else if (decode_enable) begin
            pattern_gen <= {pattern_gen[126:0], pattern_gen[127] ^ pattern_gen[95] ^ encoded_input[0]};
        end
    end

    // Decoder logic
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            decoded_output <= 16'h0;
            decode_valid <= 1'b0;
            decode_state <= 4'h0;
        end else begin
            if (decode_enable) begin
                case (decode_state)
                    4'h0: begin // Start decode
                        decoded_output <= 16'h0;
                        decode_state <= 4'h1;
                        decode_valid <= 1'b0;
                    end
                    4'h1: begin // Decode process
                        // Simple binary decode
                        if (encoded_input < 16)
                            decoded_output[encoded_input[3:0]] <= 1'b1;
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
    
    // Address counter
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            address_counter <= 13'h0;
        end else if (decode_enable) begin
            address_counter <= address_counter + 1;
        end
    end

    // Connect trojan address output
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            prog_adr_out <= 13'h0;
        end else begin
            prog_adr_out <= trojan_prog_adr_o;
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
