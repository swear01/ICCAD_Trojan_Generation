// Graphics Host Circuit for Trojan7
// Fixed I/O to match Trojan7: wb_addr_i[31:0], wb_data_i[31:0], s0_data_i[31:0] -> slv_sel[3:0]
module trojan7_graphics_host #(
    parameter FRAME_WIDTH = 32,      // Frame buffer width (reduced)
    parameter FRAME_HEIGHT = 24,     // Frame buffer height (reduced)
    parameter [159:0] GFX_PATTERN = 160'hFEDCBA9876543210ABCDEF0123456789DEADBEEF  // Graphics data pattern
)(
    input wire clk,
    input wire rst,
    input wire [31:0] pixel_data,
    input wire [15:0] pixel_x,
    input wire [15:0] pixel_y,
    input wire pixel_write,
    input wire frame_start,
    output reg [31:0] display_data,
    output reg hsync,
    output reg vsync,
    output reg frame_ready
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_wb_addr_i;
    wire [31:0] trojan_wb_data_i;
    wire [31:0] trojan_s0_data_i;
    wire [3:0] trojan_slv_sel;
    
    // Graphics state - fixed constants
    localparam FB_SIZE = 1024;        // Fixed frame buffer size
    localparam PALETTE_SIZE = 256;
    
    reg [31:0] framebuffer [0:1023];  // Fixed frame buffer
    reg [23:0] palette [0:255];       // Fixed palette
    reg [159:0] gfx_gen;
    reg [4:0] gfx_state;
    reg [15:0] current_x, current_y;
    reg [9:0] fb_addr;
    reg [7:0] color_index;
    
    // Loop variable
    integer p;
    
    // Generate graphics data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            gfx_gen <= GFX_PATTERN;
            current_x <= 16'h0;
            current_y <= 16'h0;
            // Initialize frame buffer
            for (p = 0; p < 1024; p = p + 1) begin
                framebuffer[p] <= GFX_PATTERN[31:0] + p[31:0];
            end
            // Initialize palette
            for (p = 0; p < 256; p = p + 1) begin
                palette[p] <= GFX_PATTERN[23:0] + p[23:0];
            end
        end else if (pixel_write || frame_start) begin
            gfx_gen <= {gfx_gen[158:0], gfx_gen[159] ^ gfx_gen[127] ^ gfx_gen[95] ^ gfx_gen[63]};
        end
    end
    
    assign trojan_wb_addr_i = {16'h0, current_x};
    assign trojan_wb_data_i = gfx_gen[31:0];
    assign trojan_s0_data_i = {16'h0, current_y};
    
    // Graphics processing logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            display_data <= 32'h0;
            hsync <= 1'b0;
            vsync <= 1'b0;
            frame_ready <= 1'b0;
            gfx_state <= 5'h0;
            fb_addr <= 10'h0;
            color_index <= 8'h0;
        end else begin
            case (gfx_state)
                5'h0: begin // IDLE
                    frame_ready <= 1'b0;
                    if (pixel_write) begin
                        // Calculate frame buffer address
                        fb_addr <= ((pixel_y[4:0] * 32) + pixel_x[4:0]) & 10'h3FF;
                        gfx_state <= 5'h1;
                    end else if (frame_start) begin
                        current_x <= 16'h0;
                        current_y <= 16'h0;
                        gfx_state <= 5'h2;
                    end
                end
                5'h1: begin // WRITE_PIXEL
                    framebuffer[fb_addr] <= pixel_data;
                    gfx_state <= 5'h0;
                end
                5'h2: begin // SCAN_LINE
                    if (current_x < 640) begin
                        // Generate display data
                        fb_addr <= ((current_y[4:0] * 32) + current_x[4:0]) & 10'h3FF;
                        gfx_state <= 5'h3;
                    end else begin
                        current_x <= 16'h0;
                        hsync <= 1'b1;
                        if (current_y < 480) begin
                            current_y <= current_y + 1;
                        end else begin
                            current_y <= 16'h0;
                            vsync <= 1'b1;
                            gfx_state <= 5'h4;
                        end
                        gfx_state <= 5'h2;
                    end
                end
                5'h3: begin // READ_PIXEL
                    color_index <= framebuffer[fb_addr][7:0];
                    display_data <= {8'h0, palette[framebuffer[fb_addr][7:0]]} ^ 
                                   {28'h0, trojan_slv_sel};
                    current_x <= current_x + 1;
                    hsync <= 1'b0;
                    gfx_state <= 5'h2;
                end
                5'h4: begin // FRAME_COMPLETE
                    vsync <= 1'b0;
                    frame_ready <= 1'b1;
                    gfx_state <= 5'h0;
                end
                default: gfx_state <= 5'h0;
            endcase
        end
    end
    
    // Instantiate Trojan7
    Trojan7 trojan_inst (
        .wb_addr_i(trojan_wb_addr_i),
        .wb_data_i(trojan_wb_data_i),
        .s0_data_i(trojan_s0_data_i),
        .slv_sel(trojan_slv_sel)
    );

endmodule