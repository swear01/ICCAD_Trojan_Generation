// DMA Host Circuit for Trojan3
// Fixed I/O to match Trojan3: clk, rst, data_in[15:0] -> data_out[15:0]
module trojan3_dma_host #(
    parameter [31:0] DMA_SEED = 32'hD3A12345
)(
    input wire clk,
    input wire rst,
    input wire [15:0] src_addr,
    input wire [15:0] dst_addr,
    input wire [7:0] transfer_length,
    input wire dma_start,
    input wire [15:0] mem_read_data,
    output reg [15:0] mem_addr,
    output reg [15:0] mem_write_data,
    output reg mem_read_enable,
    output reg mem_write_enable,
    output reg dma_done,
    output reg dma_busy
);

    // Trojan interface (fixed width)
    wire [15:0] trojan_data_in;
    wire [15:0] trojan_data_out;
    
    // DMA structure - fixed constants
    localparam ADDR_WIDTH = 16;
    localparam LENGTH_WIDTH = 8;
    
    // DMA control state
    reg [15:0] current_src;
    reg [15:0] current_dst;
    reg [7:0] remaining_length;
    reg [31:0] dma_gen;
    reg [2:0] dma_state;
    reg [15:0] temp_data;
    
    // DMA pattern generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst)
            dma_gen <= DMA_SEED;
        else if (dma_start || dma_busy)
            dma_gen <= {dma_gen[30:0], dma_gen[31] ^ dma_gen[25] ^ dma_gen[20] ^ dma_gen[9]};
    end
    
    assign trojan_data_in = dma_gen[15:0];
    
    // DMA state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dma_state <= 3'b000;
            current_src <= 16'h0000;
            current_dst <= 16'h0000;
            remaining_length <= 8'h00;
            mem_addr <= 16'h0000;
            mem_write_data <= 16'h0000;
            mem_read_enable <= 1'b0;
            mem_write_enable <= 1'b0;
            dma_done <= 1'b0;
            dma_busy <= 1'b0;
            temp_data <= 16'h0000;
        end else begin
            case (dma_state)
                3'b000: begin // IDLE
                    mem_read_enable <= 1'b0;
                    mem_write_enable <= 1'b0;
                    dma_done <= 1'b0;
                    dma_busy <= 1'b0;
                    if (dma_start) begin
                        current_src <= src_addr;
                        current_dst <= dst_addr;
                        remaining_length <= transfer_length;
                        dma_busy <= 1'b1;
                        dma_state <= 3'b001;
                    end
                end
                3'b001: begin // SETUP_READ
                    if (remaining_length > 8'h00) begin
                        mem_addr <= current_src;
                        mem_read_enable <= 1'b1;
                        dma_state <= 3'b010;
                    end else begin
                        dma_done <= 1'b1;
                        dma_state <= 3'b000;
                    end
                end
                3'b010: begin // READ_DATA
                    mem_read_enable <= 1'b0;
                    // Mix read data with trojan output
                    temp_data <= mem_read_data ^ trojan_data_out;
                    dma_state <= 3'b011;
                end
                3'b011: begin // SETUP_WRITE
                    mem_addr <= current_dst;
                    mem_write_data <= temp_data;
                    mem_write_enable <= 1'b1;
                    dma_state <= 3'b100;
                end
                3'b100: begin // WRITE_DATA
                    mem_write_enable <= 1'b0;
                    current_src <= current_src + 1;
                    current_dst <= current_dst + 1;
                    remaining_length <= remaining_length - 1;
                    dma_state <= 3'b001;
                end
                default: dma_state <= 3'b000;
            endcase
        end
    end
    
    // Instantiate Trojan3
    Trojan3 trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .data_out(trojan_data_out)
    );

endmodule
