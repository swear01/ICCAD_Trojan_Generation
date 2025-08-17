// Datapath Host Circuit for Trojan0
// Interface: clk, rst, key[KEY_WIDTH-1:0] -> load[LOAD_WIDTH-1:0]
module trojan0_datapath_host #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter KEY_WIDTH = 128,
    parameter LOAD_WIDTH = 64
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] a_in,
    input wire [DATA_WIDTH-1:0] b_in,
    input wire [3:0] alu_op,
    input wire [ADDR_WIDTH-1:0] addr_in,
    output reg [DATA_WIDTH-1:0] result_out,
    output reg [ADDR_WIDTH-1:0] addr_out,
    output reg valid_out,
    
    // Internal trojan signals
    wire [KEY_WIDTH-1:0] trojan_key,
    wire [LOAD_WIDTH-1:0] trojan_load
);

    // Internal signals
    reg [DATA_WIDTH-1:0] alu_result;
    reg [DATA_WIDTH-1:0] mult_result;
    reg [DATA_WIDTH-1:0] shift_result;
    reg [1:0] operation_mode;
    reg [7:0] cycle_counter;
    reg [KEY_WIDTH-1:0] key_generator;
    
    // Key generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst)
            key_generator <= {{(KEY_WIDTH-32){1'b0}}, 32'h0123CDEF};
        else
            key_generator <= {key_generator[KEY_WIDTH-2:0], key_generator[KEY_WIDTH-1] ^ key_generator[7]};
    end
    
    assign trojan_key = key_generator;
    
    // ALU operations
    always @(*) begin
        case (alu_op[2:0])
            3'b000: alu_result = a_in + b_in;
            3'b001: alu_result = a_in - b_in;
            3'b010: alu_result = a_in & b_in;
            3'b011: alu_result = a_in | b_in;
            3'b100: alu_result = a_in ^ b_in;
            3'b101: alu_result = ~(a_in & b_in);
            3'b110: alu_result = (a_in < b_in) ? {{(DATA_WIDTH-1){1'b0}}, 1'b1} : {DATA_WIDTH{1'b0}};
            3'b111: alu_result = a_in;
            default: alu_result = {DATA_WIDTH{1'b0}};
        endcase
    end
    
    // Multiplier
    always @(*) begin
        if (DATA_WIDTH >= 16)
            mult_result = a_in[15:0] * b_in[15:0];
        else
            mult_result = a_in * b_in;
    end
    
    // Barrel shifter
    always @(*) begin
        if (alu_op[3])
            shift_result = a_in << b_in[4:0];
        else
            shift_result = a_in >> b_in[4:0];
    end
    
    // Cycle counter
    always @(posedge clk or posedge rst) begin
        if (rst)
            cycle_counter <= 8'b0;
        else
            cycle_counter <= cycle_counter + 1;
    end
    
    // Operation mode selection
    always @(posedge clk or posedge rst) begin
        if (rst)
            operation_mode <= 2'b00;
        else if (cycle_counter[3:0] == 4'hF)
            operation_mode <= operation_mode + 1;
    end
    
    // Result output with trojan load integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result_out <= {DATA_WIDTH{1'b0}};
            addr_out <= {ADDR_WIDTH{1'b0}};
            valid_out <= 1'b0;
        end else begin
            case (operation_mode)
                2'b00: begin
                    result_out <= alu_result;
                    addr_out <= addr_in + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                end
                2'b01: begin
                    result_out <= mult_result;
                    addr_out <= addr_in + {{(ADDR_WIDTH-2){1'b0}}, 2'b10};
                end
                2'b10: begin
                    result_out <= shift_result;
                    addr_out <= addr_in + {{(ADDR_WIDTH-2){1'b0}}, 2'b11};
                end
                2'b11: begin
                    if (DATA_WIDTH <= LOAD_WIDTH)
                        result_out <= a_in ^ b_in ^ trojan_load[DATA_WIDTH-1:0];
                    else
                        result_out <= a_in ^ b_in ^ {{(DATA_WIDTH-LOAD_WIDTH){1'b0}}, trojan_load};
                    addr_out <= addr_in;
                end
                default: begin
                    result_out <= {DATA_WIDTH{1'b0}};
                    addr_out <= {ADDR_WIDTH{1'b0}};
                end
            endcase
            valid_out <= 1'b1;
        end
    end
    
    // Instantiate Trojan0 with width adaptation
    generate
        if (KEY_WIDTH == 128 && LOAD_WIDTH == 64) begin: trojan_direct
            Trojan0 trojan_inst (
                .clk(clk),
                .rst(rst),
                .key(trojan_key),
                .load(trojan_load)
            );
        end else begin: trojan_adapted
            wire [127:0] adapted_key;
            wire [63:0] adapted_load;
            
            // Adapt key width
            if (KEY_WIDTH >= 128) begin
                assign adapted_key = trojan_key[127:0];
            end else begin
                assign adapted_key = {{(128-KEY_WIDTH){1'b0}}, trojan_key};
            end
            
            Trojan0 trojan_inst (
                .clk(clk),
                .rst(rst),
                .key(adapted_key),
                .load(adapted_load)
            );
            
            // Adapt load width
            if (LOAD_WIDTH >= 64) begin
                assign trojan_load = {{(LOAD_WIDTH-64){1'b0}}, adapted_load};
            end else begin
                assign trojan_load = adapted_load[LOAD_WIDTH-1:0];
            end
        end
    endgenerate

endmodule