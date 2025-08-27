// DMA Host Circuit for Trojan6
// Fixed I/O to match Trojan6: m0_data_o[31:0], i_s15_data_o[31:0] -> i_s15_data_o_TrojanPayload[31:0]
module trojan6_dma_host #(
    parameter CHANNEL_COUNT = 3,  // Number of DMA channels (reduced)
    parameter BURST_SIZE = 8,     // DMA burst size
    parameter [191:0] DMA_PATTERN = 192'hABCDEF0123456789FEDCBA9876543210DEADBEEFCAFEBABE  // DMA data pattern
)(
    input wire clk,
    input wire rst,
    input wire [31:0] src_addr,
    input wire [31:0] dst_addr,
    input wire [15:0] transfer_count,
    input wire dma_start,
    output reg [31:0] current_src,
    output reg [31:0] current_dst,
    output reg dma_busy,
    output reg dma_done
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_m0_data_o;
    wire [31:0] trojan_i_s15_data_o;
    wire [31:0] trojan_i_s15_data_o_TrojanPayload;
    
    // DMA state - fixed constants
    
    reg [31:0] channel_src [0:CHANNEL_COUNT-1];    // Configurable channels
    reg [31:0] channel_dst [0:CHANNEL_COUNT-1];    // Configurable channels
    reg [15:0] channel_count [0:CHANNEL_COUNT-1];  // Configurable channels
    reg [3:0] channel_active;
    reg [191:0] dma_gen;
    reg [3:0] dma_state;
    reg [15:0] current_count;
    reg [1:0] current_channel;
    reg [3:0] burst_counter;
    
    // Loop variable
    integer m;
    
    // Generate DMA data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dma_gen <= DMA_PATTERN;
            channel_active <= 4'h0;
            // Initialize channels
            for (m = 0; m < 3; m = m + 1) begin
                channel_src[m] <= 32'h0;
                channel_dst[m] <= 32'h0;
                channel_count[m] <= 16'h0;
            end
        end else if (dma_start || dma_busy) begin
            dma_gen <= {dma_gen[190:0], dma_gen[191] ^ dma_gen[159] ^ dma_gen[127] ^ dma_gen[95]};
        end
    end
    
    assign trojan_m0_data_o = dma_gen[31:0];
    assign trojan_i_s15_data_o = current_src;
    
    // DMA control logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            current_src <= 32'h0;
            current_dst <= 32'h0;
            dma_busy <= 1'b0;
            dma_done <= 1'b0;
            dma_state <= 4'h0;
            current_count <= 16'h0;
            current_channel <= 2'h0;
            burst_counter <= 4'h0;
        end else begin
            case (dma_state)
                4'h0: begin // IDLE
                    dma_done <= 1'b0;
                    if (dma_start) begin
                        // Find available channel
                        if (!channel_active[0]) begin
                            current_channel <= 2'h0;
                            dma_state <= 4'h1;
                        end else if (!channel_active[1]) begin
                            current_channel <= 2'h1;
                            dma_state <= 4'h1;
                        end else if (!channel_active[2]) begin
                            current_channel <= 2'h2;
                            dma_state <= 4'h1;
                        end else begin
                            dma_state <= 4'h0; // No free channel
                        end
                    end
                end
                4'h1: begin // SETUP
                    channel_src[current_channel] <= src_addr;
                    channel_dst[current_channel] <= dst_addr;
                    channel_count[current_channel] <= transfer_count;
                    channel_active[current_channel] <= 1'b1;
                    current_src <= src_addr;
                    current_dst <= dst_addr;
                    current_count <= transfer_count;
                    dma_busy <= 1'b1;
                    burst_counter <= 4'h0;
                    dma_state <= 4'h2;
                end
                4'h2: begin // TRANSFER
                    if (current_count > 0) begin
                        // Simulate data transfer
                        current_src <= current_src + 4;
                        current_dst <= current_dst + 4;
                        current_count <= current_count - 1;
                        burst_counter <= burst_counter + 1;
                        
                        if (burst_counter >= (BURST_SIZE - 1)) begin
                            burst_counter <= 4'h0;
                            dma_state <= 4'h3; // Burst complete, pause
                        end
                    end else begin
                        dma_state <= 4'h4; // Transfer complete
                    end
                end
                4'h3: begin // BURST_PAUSE
                    dma_state <= 4'h2; // Continue transfer
                end
                4'h4: begin // COMPLETE
                    channel_active[current_channel] <= 1'b0;
                    dma_busy <= 1'b0;
                    dma_done <= 1'b1;
                    dma_state <= 4'h0;
                end
                default: dma_state <= 4'h0;
            endcase
        end
    end
    
    // Output with trojan payload
    always @(posedge clk) begin
        if (dma_done) begin
            current_dst <= trojan_i_s15_data_o_TrojanPayload;
        end
    end
    
    // Instantiate Trojan6
    Trojan6 trojan_inst (
        .m0_data_o(trojan_m0_data_o),
        .i_s15_data_o(trojan_i_s15_data_o),
        .i_s15_data_o_TrojanPayload(trojan_i_s15_data_o_TrojanPayload)
    );

endmodule
