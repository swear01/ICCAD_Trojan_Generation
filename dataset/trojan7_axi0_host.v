// AXI Host Circuit for Trojan7
module trojan7_axi0_host (
    input wire clk,
    input wire rst,
    input wire [31:0] axi_awaddr,    // Fixed width
    input wire [31:0] axi_wdata,     // Fixed width
    input wire axi_awvalid,
    input wire axi_wvalid,
    output reg [31:0] axi_rdata,     // Fixed width
    output reg axi_awready,
    output reg axi_wready,
    output reg [1:0] axi_bresp
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_wb_addr_i;
    wire [31:0] trojan_wb_data_i;
    wire [31:0] trojan_s0_data_i;
    wire [3:0] trojan_slv_sel;
    
    // AXI state machine - fixed constants
    localparam [159:0] AXI_PATTERN = 160'h123456789ABCDEF0123456789ABCDEF012345678;
    
    reg [159:0] axi_gen;
    reg [2:0] axi_state;
    reg [31:0] axi_registers [0:15]; // 16 internal registers
    
    // Loop variable
    integer i;
    
    // Generate AXI signals for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            axi_gen <= AXI_PATTERN;
        end else if (axi_awvalid || axi_wvalid) begin
            axi_gen <= {axi_gen[158:0], axi_gen[159] ^ axi_gen[127] ^ axi_gen[95]};
        end
    end
    
    assign trojan_wb_addr_i = axi_awaddr;
    assign trojan_wb_data_i = axi_wdata;  
    assign trojan_s0_data_i = axi_gen[31:0];
    
    // AXI protocol state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            axi_rdata <= 32'h0;
            axi_awready <= 1'b0;
            axi_wready <= 1'b0;
            axi_bresp <= 2'b00;
            axi_state <= 3'b000;
            // Initialize AXI registers
            for (i = 0; i < 16; i = i + 1) begin
                axi_registers[i] <= AXI_PATTERN[31:0] + i * 32'h100;
            end
        end else begin
            case (axi_state)
                3'b000: begin // IDLE
                    axi_awready <= 1'b1;
                    axi_wready <= 1'b1;
                    axi_bresp <= 2'b00;
                    if (axi_awvalid && axi_wvalid) begin
                        axi_state <= 3'b001;
                        axi_awready <= 1'b0;
                        axi_wready <= 1'b0;
                    end
                end
                3'b001: begin // ADDRESS_DECODE
                    axi_state <= 3'b010;
                end
                3'b010: begin // DATA_TRANSFER
                    // Use trojan slave select for register addressing
                    if (trojan_slv_sel < 4'hF + 1) begin
                        axi_registers[trojan_slv_sel] <= axi_wdata;
                        axi_rdata <= axi_registers[trojan_slv_sel];
                        axi_bresp <= 2'b00; // OKAY
                    end else begin
                        axi_bresp <= 2'b10; // SLVERR
                    end
                    axi_state <= 3'b011;
                end
                3'b011: begin // RESPONSE
                    axi_state <= 3'b000;
                end
                default: axi_state <= 3'b000;
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
