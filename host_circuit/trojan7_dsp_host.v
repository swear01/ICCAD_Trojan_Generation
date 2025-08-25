// DSP Host Circuit for Trojan7
// Fixed I/O to match Trojan7: wb_addr_i[31:0], wb_data_i[31:0], s0_data_i[31:0] -> slv_sel[3:0]
module trojan7_dsp_host #(
    parameter DSP_STAGES = 4,         // Number of DSP pipeline stages
    parameter FILTER_TAPS = 8,        // Number of filter taps
    parameter [127:0] DSP_PATTERN = 128'h0123456789ABCDEF0123456789ABCDEF  // DSP data pattern
)(
    input wire clk,
    input wire rst,
    input wire [31:0] sample_in,
    input wire [15:0] coeff_addr,
    input wire [31:0] coeff_data,
    input wire coeff_write,
    input wire dsp_enable,
    output reg [31:0] sample_out,
    output reg dsp_ready
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_wb_addr_i;
    wire [31:0] trojan_wb_data_i;
    wire [31:0] trojan_s0_data_i;
    wire [3:0] trojan_slv_sel;
    
    // DSP state - fixed constants
    localparam MAX_TAPS = 16;
    localparam ADDR_WIDTH = 12;
    
    reg [31:0] filter_coeffs [0:15];  // Fixed to 16 coefficients
    reg [31:0] delay_line [0:15];     // Fixed to 16 delays
    reg [31:0] multiply_result [0:7]; // Fixed to 8 multipliers
    reg [127:0] dsp_gen;
    reg [3:0] dsp_state;
    reg [3:0] current_stage;
    reg [63:0] accumulator;
    
    // Loop variable
    integer k;
    
    // Generate DSP data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dsp_gen <= DSP_PATTERN;
            // Initialize coefficients
            for (k = 0; k < 16; k = k + 1) begin
                filter_coeffs[k] <= DSP_PATTERN[31:0] + k;
                delay_line[k] <= 32'h0;
            end
            for (k = 0; k < 8; k = k + 1) begin
                multiply_result[k] <= 32'h0;
            end
        end else if (dsp_enable) begin
            dsp_gen <= {dsp_gen[126:0], dsp_gen[127] ^ dsp_gen[95] ^ dsp_gen[63] ^ dsp_gen[31]};
        end
    end
    
    assign trojan_wb_addr_i = {20'h0, coeff_addr[11:0]};
    assign trojan_wb_data_i = dsp_gen[31:0];
    assign trojan_s0_data_i = sample_in;
    
    // DSP processing logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sample_out <= 32'h0;
            dsp_ready <= 1'b0;
            dsp_state <= 4'h0;
            current_stage <= 4'h0;
            accumulator <= 64'h0;
        end else begin
            case (dsp_state)
                4'h0: begin // IDLE
                    dsp_ready <= 1'b0;
                    if (coeff_write) begin
                        filter_coeffs[coeff_addr[3:0]] <= coeff_data;
                    end else if (dsp_enable) begin
                        // Shift delay line
                        for (k = 15; k > 0; k = k - 1) begin
                            delay_line[k] <= delay_line[k-1];
                        end
                        delay_line[0] <= sample_in;
                        current_stage <= 4'h0;
                        accumulator <= 64'h0;
                        dsp_state <= 4'h1;
                    end
                end
                4'h1: begin // MULTIPLY
                    if (current_stage < FILTER_TAPS) begin
                        multiply_result[current_stage[2:0]] <= delay_line[current_stage] * filter_coeffs[current_stage];
                        current_stage <= current_stage + 1;
                    end else begin
                        dsp_state <= 4'h2;
                    end
                end
                4'h2: begin // ACCUMULATE
                    accumulator <= {32'h0, multiply_result[0]} + {32'h0, multiply_result[1]} + 
                                  {32'h0, multiply_result[2]} + {32'h0, multiply_result[3]} +
                                  {32'h0, multiply_result[4]} + {32'h0, multiply_result[5]} +
                                  {32'h0, multiply_result[6]} + {32'h0, multiply_result[7]};
                    dsp_state <= 4'h3;
                end
                4'h3: begin // OUTPUT
                    sample_out <= accumulator[31:0] ^ {28'h0, trojan_slv_sel};
                    dsp_ready <= 1'b1;
                    dsp_state <= 4'h0;
                end
                default: dsp_state <= 4'h0;
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
