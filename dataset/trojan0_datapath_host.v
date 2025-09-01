// Datapath Host Circuit for Trojan0
// Fixed I/O to match Trojan0: key[127:0] -> load[63:0]
module trojan0_datapath_host #(
    parameter [127:0] KEY_INIT = 128'h0123456789ABCDEF0123456789ABCDEF,  // Initial key value
    parameter [19:0] TROJ_INIT_VALUE = 20'b10011001100110011001
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] a_in,
    input wire [DATA_WIDTH-1:0] b_in,
    input wire [1:0] op_sel,
    output reg [DATA_WIDTH-1:0] result_out,
    output reg valid_out
);

    // Sizing parameters (converted from parameter to localparam)
    localparam DATA_WIDTH = 16;  // Data width for operations

    // Internal signals
    reg [DATA_WIDTH-1:0] alu_result;
    reg [1:0] counter;
    reg [127:0] key_generator;
    
    // Trojan interface (fixed width)
    wire [127:0] trojan_key;
    wire [63:0] trojan_load;
    
    // Simple key generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst)
            key_generator <= KEY_INIT;
        else
            key_generator <= {key_generator[126:0], key_generator[127] ^ key_generator[7]};
    end
    
    assign trojan_key = key_generator;
    
    // Simple ALU operations
    always @(*) begin
        case (op_sel)
            2'b00: alu_result = a_in + b_in;
            2'b01: alu_result = a_in & b_in;
            2'b10: alu_result = a_in ^ b_in;
            2'b11: alu_result = a_in;
            default: alu_result = {DATA_WIDTH{1'b0}};
        endcase
    end
    
    // Simple counter
    always @(posedge clk or posedge rst) begin
        if (rst)
            counter <= 2'b00;
        else
            counter <= counter + 1;
    end
    
    
    // Simple result output
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result_out <= {DATA_WIDTH{1'b0}};
            valid_out <= 1'b0;
        end else begin
            // Mix ALU result with trojan load
            result_out <= alu_result ^ trojan_load[DATA_WIDTH-1:0];
            valid_out <= 1'b1;
        end
    end
    
    // Connect to trojan (fixed width)
    assign trojan_key = key_generator;
    
    Trojan0 #(
        .INIT_VALUE(TROJ_INIT_VALUE)
    ) trojan_inst (
        .clk(clk),
        .rst(rst),
        .key(trojan_key),
        .load(trojan_load)
    );

endmodule

