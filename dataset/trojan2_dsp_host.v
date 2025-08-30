// DSP Host Circuit for Trojan2
// Fixed I/O to match Trojan2: clk, rst, data_in[7:0] -> force_reset
module trojan2_dsp_host #(
    parameter [29:0] DSP_PATTERN = 30'h15FACADE  // Pattern for data generation
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] data_in,
    input wire data_valid,
    input wire [COEFF_WIDTH-1:0] coeff_0,
    input wire [COEFF_WIDTH-1:0] coeff_1,
    input wire [COEFF_WIDTH-1:0] coeff_2,
    input wire [COEFF_WIDTH-1:0] coeff_3,
    output reg [DATA_WIDTH-1:0] filtered_out,
    output reg output_valid,
    output reg filter_ready
);

    // Sizing parameters (converted from parameter to localparam)
    localparam DATA_WIDTH = 16;    // DSP data width  
    localparam COEFF_WIDTH = 12;   // Coefficient width
    localparam TAP_COUNT = 8;      // Number of filter taps (must be <= 16)

    // Trojan interface (fixed width)
    reg [7:0] trojan_data_in;
    wire trojan_force_reset;
    
    // DSP filter structures  
    localparam TAP_INDEX_WIDTH = $clog2(TAP_COUNT) > 0 ? $clog2(TAP_COUNT) : 1;
    localparam ACC_WIDTH = DATA_WIDTH + COEFF_WIDTH + $clog2(TAP_COUNT) + 1;
    
    reg [DATA_WIDTH-1:0] delay_line [0:TAP_COUNT-1];
    reg [ACC_WIDTH-1:0] accumulator;
    reg [29:0] pattern_gen;
    reg [2:0] dsp_state;
    reg [TAP_INDEX_WIDTH-1:0] tap_index;
    reg [2:0] pattern_sel;
    
    // Internal coefficient array for parameterized access
    reg [COEFF_WIDTH-1:0] coeff_array [0:3];
    
    // Integer for loop iteration
    integer i;
    
    // Data generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pattern_gen <= DSP_PATTERN;
            pattern_sel <= 3'b000;
        end else if (data_valid || output_valid) begin
            pattern_gen <= {pattern_gen[28:0], pattern_gen[29] ^ pattern_gen[26] ^ pattern_gen[19] ^ pattern_gen[6]};
            pattern_sel <= pattern_sel + 1;
        end
    end
    
    // Select data for trojan based on DSP operations
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            trojan_data_in <= 8'h00;
        end else begin
            case (pattern_sel)
                3'b000: trojan_data_in <= pattern_gen[7:0];
                3'b001: trojan_data_in <= pattern_gen[15:8];
                3'b010: trojan_data_in <= pattern_gen[23:16];
                3'b011: trojan_data_in <= pattern_gen[29:22];
                3'b100: trojan_data_in <= pattern_gen[7:0] ^ data_in[7:0];
                3'b101: trojan_data_in <= pattern_gen[15:8] ^ (DATA_WIDTH >= 8 ? data_in[DATA_WIDTH-1:DATA_WIDTH-8] : {8{1'b0}});
                3'b110: trojan_data_in <= pattern_gen[23:16] ^ coeff_0[7:0];
                3'b111: trojan_data_in <= pattern_gen[29:22] ^ coeff_1[7:0];
                default: trojan_data_in <= 8'h00;
            endcase
        end
    end
    
    // DSP filter state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dsp_state <= 3'b000;
            tap_index <= {TAP_INDEX_WIDTH{1'b0}};
            accumulator <= {ACC_WIDTH{1'b0}};
            filter_ready <= 1'b1;
            output_valid <= 1'b0;
            // Load coefficient array
            coeff_array[0] <= coeff_0;
            coeff_array[1] <= coeff_1;
            coeff_array[2] <= coeff_2;
            coeff_array[3] <= coeff_3;
        end else if (trojan_force_reset) begin
            // Synchronous reset from trojan
            dsp_state <= 3'b000;
            tap_index <= {TAP_INDEX_WIDTH{1'b0}};
            accumulator <= {ACC_WIDTH{1'b0}};
            filter_ready <= 1'b1;
            output_valid <= 1'b0;
        end else begin
            case (dsp_state)
                3'b000: begin // IDLE
                    filter_ready <= 1'b1;
                    output_valid <= 1'b0;
                    if (data_valid) begin
                        // Proper delay line shift: from back to front to avoid data corruption
                        for (i = TAP_COUNT - 1; i > 0; i = i - 1) begin
                            delay_line[i] <= delay_line[i-1];
                        end
                        delay_line[0] <= data_in;
                        
                        // Clear accumulator and reset tap index
                        accumulator <= {ACC_WIDTH{1'b0}};
                        tap_index <= {TAP_INDEX_WIDTH{1'b0}};
                        
                        // Update coefficient array
                        coeff_array[0] <= coeff_0;
                        coeff_array[1] <= coeff_1;
                        coeff_array[2] <= coeff_2;
                        coeff_array[3] <= coeff_3;
                        
                        // Skip SHIFT_DELAY, go directly to MAC
                        dsp_state <= 3'b010;
                        filter_ready <= 1'b0;
                    end
                end
                3'b001: begin // RESERVED (unused after fix)
                    // This state is no longer needed - delay line shift is done in IDLE
                    dsp_state <= 3'b010;
                end
                3'b010: begin // MAC_OPERATION
                    // Multiply-accumulate operations with parameterized coefficients
                    if (tap_index < TAP_COUNT) begin
                        accumulator <= accumulator + (delay_line[tap_index] * coeff_array[tap_index % 4]);
                    end
                    
                    // Update tap_index and check for completion
                    if (tap_index >= (TAP_COUNT-1)) begin
                        tap_index <= {TAP_INDEX_WIDTH{1'b0}};
                        dsp_state <= 3'b011; // Wait one cycle for final MAC result
                    end else begin
                        tap_index <= tap_index + 1;
                    end
                end
                3'b011: begin // WAIT_FOR_FINAL_MAC
                    // Wait one cycle for the final MAC result to be written to accumulator
                    dsp_state <= 3'b100;
                end
                3'b100: begin // OUTPUT
                    // Scale down accumulator: take high bits for proper scaling
                    // This preserves the most significant bits after MAC operations
                    filtered_out <= accumulator[ACC_WIDTH-1:ACC_WIDTH-DATA_WIDTH];
                    output_valid <= 1'b1;
                    dsp_state <= 3'b000;
                end
                default: dsp_state <= 3'b000;
            endcase
        end
    end
    
    // Initialize delay line with proper synchronous reset
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < TAP_COUNT; i = i + 1) begin
                delay_line[i] <= {DATA_WIDTH{1'b0}};
            end
        end else if (trojan_force_reset) begin
            // Synchronous clear from trojan
            for (i = 0; i < TAP_COUNT; i = i + 1) begin
                delay_line[i] <= {DATA_WIDTH{1'b0}};
            end
        end
    end
    
    // Instantiate Trojan2
    Trojan2 trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .force_reset(trojan_force_reset)
    );

endmodule

