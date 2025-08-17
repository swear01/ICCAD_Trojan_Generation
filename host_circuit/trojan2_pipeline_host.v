// 3-Stage Pipeline Host Circuit for Trojan2
// Interface: clk, rst, data_in[7:0] -> force_reset
module trojan2_pipeline_host #(
    parameter DATA_WIDTH = 32,
    parameter PIPELINE_DEPTH = 3
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] data_in,
    input wire valid_in,
    output reg [DATA_WIDTH-1:0] data_out,
    output reg valid_out,
    output reg pipeline_busy,
    
    // Internal trojan signals
    wire [7:0] trojan_data_in,
    wire trojan_force_reset
);

    // Pipeline registers
    reg [DATA_WIDTH-1:0] stage1_data, stage2_data, stage3_data;
    reg stage1_valid, stage2_valid, stage3_valid;
    reg [DATA_WIDTH-1:0] alu_stage1, mult_stage2, final_stage3;
    reg [7:0] data_pattern_gen;
    
    // Generate 8-bit data pattern for trojan
    always @(posedge clk or posedge rst) begin
        if (rst)
            data_pattern_gen <= 8'h00;
        else if (valid_in)
            data_pattern_gen <= data_in[7:0] ^ data_pattern_gen[6:0], data_pattern_gen[7];
    end
    
    assign trojan_data_in = data_pattern_gen;
    
    // Stage 1: ALU operations
    always @(posedge clk or posedge rst) begin
        if (rst || trojan_force_reset) begin
            stage1_data <= {DATA_WIDTH{1'b0}};
            stage1_valid <= 1'b0;
            alu_stage1 <= {DATA_WIDTH{1'b0}};
        end else begin
            if (valid_in) begin
                stage1_data <= data_in;
                stage1_valid <= 1'b1;
                // ALU operations
                alu_stage1 <= data_in + {{(DATA_WIDTH-8){1'b0}}, data_pattern_gen};
            end else begin
                stage1_valid <= 1'b0;
            end
        end
    end
    
    // Stage 2: Multiplier operations
    always @(posedge clk or posedge rst) begin
        if (rst || trojan_force_reset) begin
            stage2_data <= {DATA_WIDTH{1'b0}};
            stage2_valid <= 1'b0;
            mult_stage2 <= {DATA_WIDTH{1'b0}};
        end else begin
            stage2_data <= stage1_data;
            stage2_valid <= stage1_valid;
            if (stage1_valid) begin
                if (DATA_WIDTH >= 16)
                    mult_stage2 <= alu_stage1[15:0] * stage1_data[15:0];
                else
                    mult_stage2 <= alu_stage1 * stage1_data;
            end
        end
    end
    
    // Stage 3: Final processing
    always @(posedge clk or posedge rst) begin
        if (rst || trojan_force_reset) begin
            stage3_data <= {DATA_WIDTH{1'b0}};
            stage3_valid <= 1'b0;
            final_stage3 <= {DATA_WIDTH{1'b0}};
        end else begin
            stage3_data <= stage2_data;
            stage3_valid <= stage2_valid;
            if (stage2_valid) begin
                // Final processing with trojan influence
                if (trojan_force_reset)
                    final_stage3 <= {DATA_WIDTH{1'b0}};
                else
                    final_stage3 <= mult_stage2 ^ (stage2_data << 1);
            end
        end
    end
    
    // Output assignment
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= {DATA_WIDTH{1'b0}};
            valid_out <= 1'b0;
            pipeline_busy <= 1'b0;
        end else begin
            data_out <= final_stage3;
            valid_out <= stage3_valid;
            pipeline_busy <= stage1_valid || stage2_valid || stage3_valid;
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