// FIFO Host Circuit for Trojan2
// Fixed I/O to match Trojan2: clk, rst, data_in[7:0] -> force_reset
module trojan2_fifo_host #(
    parameter DATA_WIDTH = 12,   // FIFO data width
    parameter DEPTH = 16,        // FIFO depth
    parameter [23:0] SEQUENCE_SEED = 24'hABCDEF  // Seed for data sequence generation
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] write_data,
    input wire write_enable,
    input wire read_enable,
    output reg [DATA_WIDTH-1:0] read_data,
    output reg fifo_full,
    output reg fifo_empty,
    output reg valid
);

    // Trojan interface (fixed width)
    wire [7:0] trojan_data_in;
    wire trojan_force_reset;
    
    // FIFO memory and pointers
    reg [DATA_WIDTH-1:0] fifo_mem [0:DEPTH-1];
    reg [$clog2(DEPTH):0] write_ptr, read_ptr;
    reg [$clog2(DEPTH):0] count;
    
    // Data sequence generator for trojan
    reg [23:0] seq_gen;
    reg [4:0] byte_sel;
    
    // Generate data sequence for trojan input
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            seq_gen <= SEQUENCE_SEED;
            byte_sel <= 5'b0;
        end else if (write_enable || read_enable) begin
            seq_gen <= {seq_gen[22:0], seq_gen[23] ^ seq_gen[17] ^ seq_gen[5]};
            byte_sel <= byte_sel + 1;
        end
    end
    
    assign trojan_data_in = seq_gen[7:0];
    
    // FIFO control logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            write_ptr <= {($clog2(DEPTH)+1){1'b0}};
            read_ptr <= {($clog2(DEPTH)+1){1'b0}};
            count <= {($clog2(DEPTH)+1){1'b0}};
            fifo_full <= 1'b0;
            fifo_empty <= 1'b1;
            valid <= 1'b0;
        end else if (trojan_force_reset) begin
            // Synchronous reset from trojan
            write_ptr <= {($clog2(DEPTH)+1){1'b0}};
            read_ptr <= {($clog2(DEPTH)+1){1'b0}};
            count <= {($clog2(DEPTH)+1){1'b0}};
            fifo_full <= 1'b0;
            fifo_empty <= 1'b1;
            valid <= 1'b0;
        end else begin
            // Write operation
            if (write_enable && !fifo_full) begin
                fifo_mem[write_ptr[$clog2(DEPTH)-1:0]] <= write_data;
                write_ptr <= write_ptr + 1;
                if (write_ptr == DEPTH-1)
                    write_ptr <= {($clog2(DEPTH)+1){1'b0}};
                count <= count + 1;
            end
            
            // Read operation  
            if (read_enable && !fifo_empty) begin
                read_data <= fifo_mem[read_ptr[$clog2(DEPTH)-1:0]];
                read_ptr <= read_ptr + 1;
                if (read_ptr == DEPTH-1)
                    read_ptr <= {($clog2(DEPTH)+1){1'b0}};
                count <= count - 1;
                valid <= 1'b1;
            end else begin
                valid <= 1'b0;
            end
            
            // Update flags
            fifo_full <= (count == DEPTH);
            fifo_empty <= (count == 0);
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