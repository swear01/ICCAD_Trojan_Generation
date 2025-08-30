// Data Compression Unit Host Circuit for Trojan9
// Interface: a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], mode[1:0] -> y[15:0]
module trojan9_compression_host #(
    parameter [55:0] COMP_PATTERN = 56'h123456789ABCDE  // Compression data pattern
)(
    input wire clk,
    input wire rst,
    input wire [7:0] data_in,
    input wire [1:0] comp_mode,          // 0=RLE, 1=LZ77, 2=Huffman, 3=Custom
    input wire data_valid,
    input wire compress_start,
    output reg [7:0] data_out,
    output reg [4:0] comp_length,
    output reg compress_done
);

    // Sizing parameters (converted from parameter to localparam)
    localparam BUFFER_SIZE = 32;           // Compression buffer size
    localparam DICT_SIZE = 16;             // Dictionary size for LZ compression

    // Trojan interface
    wire [7:0] trojan_a;
    wire [7:0] trojan_b;
    wire [7:0] trojan_c;
    wire [7:0] trojan_d;
    wire [7:0] trojan_e;
    wire [1:0] trojan_mode;
    wire [15:0] trojan_y;
    
    // Compression components
    reg [7:0] input_buffer [0:31];        // Fixed to 32 bytes input
    reg [7:0] output_buffer [0:31];       // Fixed to 32 bytes output
    reg [7:0] dictionary [0:15];          // Fixed to 16 bytes dictionary
    reg [55:0] comp_gen;
    reg [2:0] comp_state;
    reg [5:0] input_length;               // Length of input data
    reg [5:0] read_ptr;                   // Pointer for reading input data
    reg [4:0] output_ptr;
    reg [3:0] dict_ptr;
    reg [7:0] current_byte;
    reg [7:0] previous_byte;              // Store previous byte for RLE
    reg [3:0] run_length;
    reg [3:0] match_length;
    reg [3:0] match_offset;
    reg rle_active;                       // Flag to indicate RLE processing
    reg lz77_match_found;                 // Flag for LZ77 match
    
    // Compression controller
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            comp_gen <= COMP_PATTERN;
            comp_state <= 3'h0;
            input_length <= 6'h0;
            read_ptr <= 6'h0;
            output_ptr <= 5'h0;
            dict_ptr <= 4'h0;
            current_byte <= 8'h0;
            previous_byte <= 8'h0;
            run_length <= 4'h0;
            match_length <= 4'h0;
            match_offset <= 4'h0;
            rle_active <= 1'b0;
            lz77_match_found <= 1'b0;
            data_out <= 8'h0;
            comp_length <= 5'h0;
            compress_done <= 1'b0;
            
            // Initialize buffers
            for (integer i = 0; i < 32; i = i + 1) begin
                input_buffer[i] = COMP_PATTERN[7:0] ^ i[7:0];
                output_buffer[i] = 8'h0;
            end
            for (integer j = 0; j < 16; j = j + 1) begin
                dictionary[j] = COMP_PATTERN[15:8] ^ j[7:0];
            end
        end else begin
            comp_gen <= {comp_gen[54:0], comp_gen[55]};
            
            case (comp_state)
                3'h0: begin // IDLE
                    compress_done <= 1'b0;
                    if (data_valid) begin
                        input_buffer[input_length[4:0]] <= data_in ^ trojan_y[7:0];
                        input_length <= input_length + 1;
                    end else if (compress_start) begin
                        read_ptr <= 6'h0;
                        output_ptr <= 5'h0;
                        dict_ptr <= 4'h0;
                        rle_active <= 1'b0;
                        run_length <= 4'h1;
                        lz77_match_found <= 1'b0;
                        comp_state <= 3'h1;
                    end
                end
                3'h1: begin // ANALYZE
                    if (read_ptr < input_length) begin
                        previous_byte <= current_byte;
                        current_byte <= input_buffer[read_ptr[4:0]];
                        comp_state <= 3'h2;
                    end else begin
                        // Handle final RLE sequence if active
                        if (rle_active) begin
                            if (run_length > 1) begin
                                // Output run length and byte
                                output_buffer[output_ptr] <= {4'h0, run_length} ^ trojan_y[7:0];
                                output_buffer[output_ptr+1] <= previous_byte ^ trojan_y[15:8];
                                output_ptr <= output_ptr + 2;
                            end else begin
                                // Output single byte
                                output_buffer[output_ptr] <= previous_byte ^ trojan_y[7:0];
                                output_ptr <= output_ptr + 1;
                            end
                            rle_active <= 1'b0;
                        end
                        comp_state <= 3'h4;  // OUTPUT
                    end
                end
                3'h2: begin // COMPRESS
                    case (comp_mode)
                        2'b00: begin // RLE (Run Length Encoding)
                            if (!rle_active) begin
                                // Start new sequence
                                rle_active <= 1'b1;
                                run_length <= 4'h1;
                                read_ptr <= read_ptr + 1;
                                comp_state <= 3'h1;  // Go back to ANALYZE
                            end else if (current_byte == previous_byte && run_length < 15) begin
                                // Continue sequence
                                run_length <= run_length + 1;
                                read_ptr <= read_ptr + 1;
                                comp_state <= 3'h1;  // Go back to ANALYZE
                            end else begin
                                // End of sequence
                                if (run_length > 1) begin
                                    // Output run length and byte
                                    output_buffer[output_ptr] <= {4'h0, run_length} ^ trojan_y[7:0];
                                    output_buffer[output_ptr+1] <= previous_byte ^ trojan_y[15:8];
                                    output_ptr <= output_ptr + 2;
                                end else begin
                                    // Output single byte
                                    output_buffer[output_ptr] <= previous_byte ^ trojan_y[7:0];
                                    output_ptr <= output_ptr + 1;
                                end
                                rle_active <= 1'b0;
                                run_length <= 4'h1;
                                comp_state <= 3'h1;  // Go back to ANALYZE
                            end
                        end
                        2'b01: begin // LZ77 (simplified)
                            // Search in dictionary for match
                            lz77_match_found <= 1'b0;
                            for (integer k = 0; k < 16; k = k + 1) begin
                                if (dictionary[k] == current_byte) begin
                                    match_offset <= k[3:0];
                                    lz77_match_found <= 1'b1;
                                end
                            end
                            
                            if (lz77_match_found) begin
                                output_buffer[output_ptr] <= {4'h0, match_offset} ^ trojan_y[7:0];
                                output_buffer[output_ptr+1] <= 8'h01 ^ trojan_y[15:8];  // Fixed length of 1
                                output_ptr <= output_ptr + 2;
                            end else begin
                                output_buffer[output_ptr] <= current_byte ^ trojan_y[7:0];
                                // Update dictionary with FIFO approach
                                dictionary[dict_ptr] <= current_byte;
                                dict_ptr <= (dict_ptr + 1) % 16;
                                output_ptr <= output_ptr + 1;
                            end
                            read_ptr <= read_ptr + 1;
                            comp_state <= 3'h1;  // Go back to ANALYZE
                        end
                        2'b10: begin // Huffman (simplified)
                            // Simple frequency-based encoding
                            if (current_byte[7:4] == 4'h0) begin
                                output_buffer[output_ptr] <= {4'h1, current_byte[3:0]} ^ trojan_y[7:0]; // Short code
                            end else begin
                                output_buffer[output_ptr] <= current_byte ^ trojan_y[7:0]; // Full byte
                            end
                            output_ptr <= output_ptr + 1;
                            read_ptr <= read_ptr + 1;
                            comp_state <= 3'h1;  // Go back to ANALYZE
                        end
                        2'b11: begin // Custom compression
                            output_buffer[output_ptr] <= current_byte ^ comp_gen[7:0] ^ trojan_y[7:0];
                            output_ptr <= output_ptr + 1;
                            read_ptr <= read_ptr + 1;
                            comp_state <= 3'h1;  // Go back to ANALYZE
                        end
                    endcase
                end
                3'h4: begin // OUTPUT
                    // Output the first byte of compressed data
                    if (output_ptr > 0) begin
                        data_out <= output_buffer[0] ^ trojan_y[7:0];
                    end else begin
                        data_out <= 8'h0;
                    end
                    comp_length <= output_ptr;
                    compress_done <= 1'b1;
                    comp_state <= 3'h0;
                end
                default: comp_state <= 3'h0;
            endcase
        end
    end
    
    // Connect trojan inputs
    assign trojan_a = comp_gen[7:0];
    assign trojan_b = data_in;
    assign trojan_c = current_byte;
    assign trojan_d = {2'h0, read_ptr};
    assign trojan_e = {6'h0, comp_mode};
    assign trojan_mode = comp_state[1:0];
    
    // Instantiate Trojan9
    Trojan9 trojan_inst (
        .a(trojan_a),
        .b(trojan_b),
        .c(trojan_c),
        .d(trojan_d),
        .e(trojan_e),
        .mode(trojan_mode),
        .y(trojan_y)
    );

endmodule
