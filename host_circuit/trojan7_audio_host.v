// Audio Host Circuit for Trojan7
// Fixed I/O to match Trojan7: wb_addr_i[31:0], wb_data_i[31:0], s0_data_i[31:0] -> slv_sel[3:0]
module trojan7_audio_host #(
    parameter SAMPLE_RATE = 44100,   // Audio sample rate
    parameter BUFFER_DEPTH = 512,    // Audio buffer depth
    parameter [95:0] AUDIO_PATTERN = 96'h123456789ABCDEF0FEDCBA98  // Audio data pattern
)(
    input wire clk,
    input wire rst,
    input wire [15:0] audio_in_left,
    input wire [15:0] audio_in_right,
    input wire audio_valid,
    input wire [7:0] volume_control,
    output reg [15:0] audio_out_left,
    output reg [15:0] audio_out_right,
    output reg audio_ready
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_wb_addr_i;
    wire [31:0] trojan_wb_data_i;
    wire [31:0] trojan_s0_data_i;
    wire [3:0] trojan_slv_sel;
    
    // Audio state - fixed constants
    localparam MAX_BUFFER = 512;
    localparam FILTER_ORDER = 8;
    
    reg [15:0] left_buffer [0:511];   // Fixed buffer size
    reg [15:0] right_buffer [0:511];  // Fixed buffer size
    reg [15:0] filter_coeffs [0:7];   // Fixed filter coefficients
    reg [95:0] audio_gen;
    reg [4:0] audio_state;
    reg [8:0] buffer_ptr;
    reg [31:0] sample_counter;
    reg [31:0] volume_mult;
    
    // Loop variable
    integer a;
    
    // Generate audio data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            audio_gen <= AUDIO_PATTERN;
            buffer_ptr <= 9'h0;
            sample_counter <= 32'h0;
            // Initialize buffers
            for (a = 0; a < 512; a = a + 1) begin
                left_buffer[a] <= 16'h0;
                right_buffer[a] <= 16'h0;
            end
            // Initialize filter coefficients
            for (a = 0; a < 8; a = a + 1) begin
                filter_coeffs[a] <= AUDIO_PATTERN[15:0] + a[15:0];
            end
        end else if (audio_valid) begin
            audio_gen <= {audio_gen[94:0], audio_gen[95] ^ audio_gen[63] ^ audio_gen[31]};
            sample_counter <= sample_counter + 1;
        end
    end
    
    assign trojan_wb_addr_i = {23'h0, buffer_ptr};
    assign trojan_wb_data_i = audio_gen[31:0];
    assign trojan_s0_data_i = {16'h0, audio_in_left};
    
    // Audio processing logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            audio_out_left <= 16'h0;
            audio_out_right <= 16'h0;
            audio_ready <= 1'b0;
            audio_state <= 5'h0;
            volume_mult <= 32'h0;
        end else begin
            case (audio_state)
                5'h0: begin // IDLE
                    audio_ready <= 1'b0;
                    if (audio_valid) begin
                        // Store input samples in buffer
                        left_buffer[buffer_ptr] <= audio_in_left;
                        right_buffer[buffer_ptr] <= audio_in_right;
                        buffer_ptr <= (buffer_ptr + 1) & 9'h1FF; // Wrap at 512
                        audio_state <= 5'h1;
                    end
                end
                5'h1: begin // PROCESS
                    // Simple volume control
                    volume_mult <= {8'h0, volume_control} * 256;
                    audio_state <= 5'h2;
                end
                5'h2: begin // FILTER
                    // Simple FIR filter (using first 4 taps)
                    audio_out_left <= ((left_buffer[buffer_ptr & 9'h1FF] * filter_coeffs[0]) +
                                      (left_buffer[(buffer_ptr - 1) & 9'h1FF] * filter_coeffs[1]) +
                                      (left_buffer[(buffer_ptr - 2) & 9'h1FF] * filter_coeffs[2]) +
                                      (left_buffer[(buffer_ptr - 3) & 9'h1FF] * filter_coeffs[3])) >> 8;
                    
                    audio_out_right <= ((right_buffer[buffer_ptr & 9'h1FF] * filter_coeffs[0]) +
                                       (right_buffer[(buffer_ptr - 1) & 9'h1FF] * filter_coeffs[1]) +
                                       (right_buffer[(buffer_ptr - 2) & 9'h1FF] * filter_coeffs[2]) +
                                       (right_buffer[(buffer_ptr - 3) & 9'h1FF] * filter_coeffs[3])) >> 8;
                    audio_state <= 5'h3;
                end
                5'h3: begin // VOLUME
                    audio_out_left <= (audio_out_left * volume_mult[23:16]) >> 8;
                    audio_out_right <= (audio_out_right * volume_mult[23:16]) >> 8;
                    audio_state <= 5'h4;
                end
                5'h4: begin // OUTPUT
                    // Apply trojan payload to audio output
                    audio_out_left <= audio_out_left ^ {12'h0, trojan_slv_sel};
                    audio_out_right <= audio_out_right ^ {12'h0, trojan_slv_sel};
                    audio_ready <= 1'b1;
                    audio_state <= 5'h0;
                end
                default: audio_state <= 5'h0;
            endcase
        end
    end
    
    // Instantiate Trojan7
    Trojan7 trojan_inst (
        .wb_addr_i(trojan_wb_addr_i),
        .wb_data_i(trojan_wb_data_i),
        .s0_data_i(trojan_s0_data_i),
        .slv_sel(trojan_slv_sel)
    );

endmodule