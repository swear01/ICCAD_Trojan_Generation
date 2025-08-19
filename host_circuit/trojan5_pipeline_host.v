// Pipeline Host Circuit for Trojan5
// Fixed I/O to match Trojan5: pon_rst_n_i, prog_dat_i[13:0], pc_reg[12:0] -> prog_adr_o[12:0]
module trojan5_pipeline_host #(
    parameter STAGE_COUNT = 5,   // Number of pipeline stages
    parameter DATA_WIDTH = 12,   // Pipeline data width
    parameter [79:0] STAGE_PATTERN = 80'h123456789ABCDEF12345  // Pattern for stage data generation
)(
    input wire clk,
    input wire pon_rst_n_i,
    input wire [DATA_WIDTH-1:0] data_in,
    input wire pipeline_enable,
    output reg [DATA_WIDTH-1:0] data_out,
    output reg pipeline_valid
);

    // Trojan interface (fixed width)
    wire [13:0] trojan_prog_dat_i;
    wire [12:0] trojan_pc_reg;
    wire [12:0] trojan_prog_adr_o;
    
    // Pipeline stages
    reg [DATA_WIDTH-1:0] pipeline_data [0:STAGE_COUNT-1];
    reg [STAGE_COUNT-1:0] pipeline_valid_stages;
    
    // Pattern generation for trojan
    reg [79:0] stage_pattern;
    reg [12:0] stage_counter;
    
    // Generate program data for trojan from pipeline state
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            stage_pattern <= STAGE_PATTERN;
            stage_counter <= 13'h0;
        end else if (pipeline_enable) begin
            stage_pattern <= {stage_pattern[77:0], stage_pattern[79] ^ stage_pattern[47] ^ stage_pattern[15]};
            stage_counter <= stage_counter + 1;
        end
    end
    
    assign trojan_prog_dat_i = stage_pattern[13:0];
    assign trojan_pc_reg = stage_counter;
    
    // Pipeline logic
    genvar i;
    generate
        for (i = 0; i < STAGE_COUNT; i = i + 1) begin: pipeline_stages
            always @(posedge clk or negedge pon_rst_n_i) begin
                if (!pon_rst_n_i) begin
                    pipeline_data[i] <= {DATA_WIDTH{1'b0}};
                    pipeline_valid_stages[i] <= 1'b0;
                end else if (pipeline_enable) begin
                    if (i == 0) begin
                        // First stage: input
                        pipeline_data[i] <= data_in;
                        pipeline_valid_stages[i] <= 1'b1;
                    end else begin
                        // Subsequent stages: propagate and process
                        pipeline_data[i] <= pipeline_data[i-1] + {{(DATA_WIDTH-1){1'b0}}, 1'b1};
                        pipeline_valid_stages[i] <= pipeline_valid_stages[i-1];
                    end
                end else begin
                    pipeline_valid_stages[i] <= 1'b0;
                end
            end
        end
    endgenerate
    
    // Output logic
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            data_out <= {DATA_WIDTH{1'b0}};
            pipeline_valid <= 1'b0;
        end else begin
            data_out <= pipeline_data[STAGE_COUNT-1];
            pipeline_valid <= pipeline_valid_stages[STAGE_COUNT-1];
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