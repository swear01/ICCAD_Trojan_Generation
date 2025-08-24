// Memory Controller Host Circuit for Trojan0
// Fixed I/O to match Trojan0: key[127:0] -> load[63:0]
module trojan0_memory_host #(
    parameter ADDR_WIDTH = 8,   // Memory address width (256 locations)
    parameter DATA_WIDTH = 16   // Data width
)(
    input wire clk,
    input wire rst,
    input wire [ADDR_WIDTH-1:0] addr,
    input wire [DATA_WIDTH-1:0] write_data,
    input wire write_enable,
    input wire read_enable,
    output reg [DATA_WIDTH-1:0] read_data,
    output reg valid
);

    // Internal trojan signals
    wire [127:0] trojan_key;
    wire [63:0] trojan_load;

    // Memory array
    reg [DATA_WIDTH-1:0] memory [0:(1<<ADDR_WIDTH)-1];
    
    // Key generation for trojan
    reg [127:0] key_generator;
    reg [7:0] addr_counter;
    
    // Simple key generation using memory addresses
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            key_generator <= 128'hFEDCBA9876543210FEDCBA9876543210;
            addr_counter <= 8'h00;
        end else if (write_enable || read_enable) begin
            key_generator <= {key_generator[119:0], key_generator[127:120] ^ addr[7:0]};
            addr_counter <= addr_counter + 1;
        end
    end
    
    // Memory operations
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            read_data <= {DATA_WIDTH{1'b0}};
            valid <= 1'b0;
        end else begin
            if (write_enable) begin
                // Mix write data with trojan load
                memory[addr] <= write_data ^ trojan_load[DATA_WIDTH-1:0];
                valid <= 1'b1;
            end else if (read_enable) begin
                read_data <= memory[addr];
                valid <= 1'b1;
            end else begin
                valid <= 1'b0;
            end
        end
    end
    
    // Connect to trojan (fixed width)
    assign trojan_key = key_generator;
    
    Trojan0 trojan_inst (
        .clk(clk),
        .rst(rst),
        .key(trojan_key),
        .load(trojan_load)
    );

endmodule

