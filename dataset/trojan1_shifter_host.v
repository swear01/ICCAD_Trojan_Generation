// Shifter Host Circuit for Trojan1
// Fixed I/O to match Trojan1: clk, rst, r1 -> trigger
module trojan1_shifter_host #(
    parameter [31:0] R1_SEED = 32'h12345678  // Seed for r1 generation
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] data_in,
    input wire load_data,
    input wire shift_enable,
    input wire shift_dir,  // 0=left, 1=right
    output reg [DATA_WIDTH-1:0] data_out,
    output reg shift_complete
);

    // Sizing parameters (converted from parameter to localparam)
    localparam DATA_WIDTH = 16;    // Shift register width
    localparam SHIFT_STEPS = 4;    // Number of shift steps per cycle

    // Trojan interface (fixed width)
    wire trojan_r1;
    wire trojan_trigger;
    
    // Internal shift register and control
    reg [DATA_WIDTH-1:0] shift_reg;
    reg [31:0] lfsr_r1;
    reg [$clog2(SHIFT_STEPS)-1:0] step_counter;
    reg shifting_active;
    
    // R1 signal generation using LFSR
    always @(posedge clk or posedge rst) begin
        if (rst)
            lfsr_r1 <= R1_SEED;
        else if (shift_enable || shifting_active)
            // Use 32-bit maximal-length LFSR: x^32 + x^22 + x^2 + x^1 + 1
            lfsr_r1 <= {lfsr_r1[30:0], lfsr_r1[31] ^ lfsr_r1[21] ^ lfsr_r1[1] ^ lfsr_r1[0]};
    end
    
    assign trojan_r1 = lfsr_r1[0];
    
    // Shift control logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            shifting_active <= 1'b0;
            step_counter <= {$clog2(SHIFT_STEPS){1'b0}};
        end else begin
            if (shift_enable && !shifting_active) begin
                shifting_active <= 1'b1;
                step_counter <= {$clog2(SHIFT_STEPS){1'b0}};
            end else if (shifting_active) begin
                if (step_counter == $clog2(SHIFT_STEPS)'(SHIFT_STEPS-1)) begin
                    shifting_active <= 1'b0;
                    step_counter <= {$clog2(SHIFT_STEPS){1'b0}};
                end else begin
                    step_counter <= step_counter + 1;
                end
            end
        end
    end
    
    // Shift register operation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            shift_reg <= {DATA_WIDTH{1'b0}};
            shift_complete <= 1'b0;
        end else if (load_data) begin
            shift_reg <= data_in;
            shift_complete <= 1'b0;
        end else if (shifting_active) begin
            if (shift_dir) begin
                // Logical right shift
                shift_reg <= {1'b0, shift_reg[DATA_WIDTH-1:1]};
            end else begin
                // Logical left shift
                shift_reg <= {shift_reg[DATA_WIDTH-2:0], 1'b0};
            end
            // Sticky shift_complete flag
            if (step_counter == $clog2(SHIFT_STEPS)'(SHIFT_STEPS-1)) begin
                shift_complete <= 1'b1;
            end
        end
    end
    
    // Output logic with trojan trigger integration
    always @(posedge clk or posedge rst) begin
        if (rst)
            data_out <= {DATA_WIDTH{1'b0}};
        else
            // Subtle trojan influence - only affect some bits
            if (trojan_trigger) begin
                data_out <= shift_reg ^ {{(DATA_WIDTH-4){1'b0}}, 4'hF};
            end else begin
                data_out <= shift_reg;
            end
    end
    
    // Instantiate Trojan1
    Trojan1 trojan_inst (
        .clk(clk),
        .rst(rst),
        .r1(trojan_r1),
        .trigger(trojan_trigger)
    );

endmodule
