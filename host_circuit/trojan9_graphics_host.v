// Graphics Processing Unit Host Circuit for Trojan9
// Interface: a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], mode[1:0] -> y[15:0]
module trojan9_graphics_host #(
    parameter PIXEL_WIDTH = 8,            // Pixel width in bits
    parameter TEXTURE_SIZE = 64,          // Texture size (64x64)
    parameter [63:0] GFX_PATTERN = 64'h123456789ABCDEF0  // Graphics data pattern
)(
    input wire clk,
    input wire rst,
    input wire [7:0] pixel_r,
    input wire [7:0] pixel_g,
    input wire [7:0] pixel_b,
    input wire [5:0] coord_x,
    input wire [5:0] coord_y,
    input wire [1:0] render_mode,         // 0=copy, 1=blend, 2=shader, 3=filter
    input wire pixel_write,
    input wire texture_read,
    output reg [7:0] out_r,
    output reg [7:0] out_g,
    output reg [7:0] out_b,
    output reg render_ready
);

    // Trojan interface
    wire [7:0] trojan_a;
    wire [7:0] trojan_b;
    wire [7:0] trojan_c;
    wire [7:0] trojan_d;
    wire [7:0] trojan_e;
    wire [1:0] trojan_mode;
    wire [15:0] trojan_y;
    
    // Graphics components
    reg [23:0] framebuffer [0:63];        // Fixed to 64 pixels (8x8 tile)
    reg [23:0] texture_memory [0:63];     // Fixed to 64 texture pixels
    reg [63:0] gfx_gen;
    reg [2:0] gfx_state;
    reg [5:0] pixel_addr;
    reg [23:0] current_pixel;
    reg [23:0] texture_pixel;
    
    // Graphics controller
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            gfx_gen <= GFX_PATTERN;
            gfx_state <= 3'h0;
            pixel_addr <= 6'h0;
            current_pixel <= 24'h0;
            texture_pixel <= 24'h0;
            out_r <= 8'h0;
            out_g <= 8'h0;
            out_b <= 8'h0;
            render_ready <= 1'b0;
            
            // Initialize framebuffer and texture
            for (integer i = 0; i < 64; i = i + 1) begin
                framebuffer[i] = GFX_PATTERN[23:0] ^ i[23:0];
                texture_memory[i] = GFX_PATTERN[47:24] ^ i[23:0];
            end
        end else begin
            gfx_gen <= {gfx_gen[62:0], gfx_gen[63]};
            
            case (gfx_state)
                3'h0: begin // IDLE
                    render_ready <= 1'b0;
                    if (pixel_write || texture_read) begin
                        pixel_addr <= {coord_y[2:0], coord_x[2:0]}; // 8x8 addressing
                        current_pixel <= {pixel_r, pixel_g, pixel_b};
                        gfx_state <= 3'h1;
                    end
                end
                3'h1: begin // FETCH
                    if (texture_read) begin
                        texture_pixel <= texture_memory[pixel_addr];
                    end else begin
                        texture_pixel <= framebuffer[pixel_addr];
                    end
                    gfx_state <= 3'h2;
                end
                3'h2: begin // PROCESS
                    case (render_mode)
                        2'b00: begin // Copy mode
                            framebuffer[pixel_addr] <= current_pixel ^ {8'h0, trojan_y};
                        end
                        2'b01: begin // Blend mode (50% blend)
                            framebuffer[pixel_addr] <= ((current_pixel >> 1) + (texture_pixel >> 1)) ^ {8'h0, trojan_y};
                        end
                        2'b10: begin // Shader mode (simple color transform)
                            framebuffer[pixel_addr] <= {
                                current_pixel[23:16] ^ trojan_y[7:0],    // R
                                current_pixel[15:8] ^ trojan_y[15:8],    // G  
                                current_pixel[7:0] ^ trojan_y[7:0]       // B
                            };
                        end
                        2'b11: begin // Filter mode (edge detection)
                            framebuffer[pixel_addr] <= (current_pixel > texture_pixel) ? 
                                                      (current_pixel - texture_pixel) : 
                                                      (texture_pixel - current_pixel);
                        end
                    endcase
                    gfx_state <= 3'h3;
                end
                3'h3: begin // OUTPUT
                    if (texture_read) begin
                        {out_r, out_g, out_b} <= texture_pixel ^ {8'h0, trojan_y};
                    end else begin
                        {out_r, out_g, out_b} <= framebuffer[pixel_addr] ^ {8'h0, trojan_y};
                    end
                    render_ready <= 1'b1;
                    gfx_state <= 3'h0;
                end
                default: gfx_state <= 3'h0;
            endcase
        end
    end
    
    // Connect trojan inputs
    assign trojan_a = gfx_gen[7:0];
    assign trojan_b = pixel_r;
    assign trojan_c = pixel_g;
    assign trojan_d = pixel_b;
    assign trojan_e = {coord_x[1:0], coord_y[1:0], render_mode, pixel_write, texture_read};
    assign trojan_mode = gfx_state[1:0];
    
    // Instantiate Trojan9
    Trojan9 trojan_inst (
        .a(trojan_a),
        .b(trojan_b),
        .c(trojan_c),
        .d(trojan_d),
        .e(trojan_e),
        .mode(trojan_mode),
        .y(trojan_y)
    );

endmodule
