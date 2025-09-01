// Decoder Host Circuit for Trojan2
module trojan2_decoder0_host #(
    parameter LFSR_INIT = 128'hFEDCBA9876543210FEDCBA9876543210
)(
    input wire clk,
    input wire pon_rst_i,
    input wire [7:0] encoded_input,  // Fixed width
    input wire decode_enable,
    output reg [15:0] decoded_output, // Fixed width
    output reg decode_valid,
    output reg [12:0] prog_adr_out    // Connect trojan address output
);

    // Trojan interface (fixed width)
    wire [7:0] trojan_data_in;
    wire trojan_force_reset;
    
    reg [127:0] lfsr;
    reg [12:0] address_counter;
    reg [3:0] decode_state;
    
    assign trojan_data_in = lfsr[7:0];
    
    // lfsr generation
    always @(posedge clk or posedge pon_rst_i) begin
        if (pon_rst_i) begin
            lfsr <= LFSR_INIT;
        end else if (decode_enable) begin
            lfsr <= {lfsr[126:0], lfsr[127] ^ lfsr[6] ^ lfsr[1] ^ lfsr[0]};
        end
    end

    // Decoder logic
    always @(posedge clk or posedge pon_rst_i) begin
        if (pon_rst_i) begin
            decoded_output <= 16'h0;
            decode_valid <= 1'b0;
            decode_state <= 4'h0;
        end else if (trojan_force_reset) begin // Force reset from trojan
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
    always @(posedge clk or posedge pon_rst_i) begin
        if (pon_rst_i) begin
            address_counter <= 13'h0;
        end else if (trojan_force_reset) begin // Force reset from trojan
            address_counter <= 13'h0;
        end else if (decode_enable) begin
            address_counter <= address_counter + 1;
        end
    end

    // Address output
    always @(posedge clk or posedge pon_rst_i) begin
        if (pon_rst_i) begin
            prog_adr_out <= 13'h0;
        end else if (trojan_force_reset) begin // Force reset from trojan
            prog_adr_out <= 13'h0;
        end else begin
            prog_adr_out <= address_counter;
        end
    end

    // Instantiate Trojan2
    Trojan2 trojan_inst (
        .clk(clk),
        .rst(pon_rst_i),
        .data_in(trojan_data_in),
        .force_reset(trojan_force_reset)
    );

endmodule
