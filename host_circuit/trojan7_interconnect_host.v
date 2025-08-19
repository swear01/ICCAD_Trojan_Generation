// Interconnect Host Circuit for Trojan7
// Fixed I/O to match Trojan7: wb_addr_i[31:0], wb_data_i[31:0], s0_data_i[31:0] -> slv_sel[3:0]
module trojan7_interconnect_host #(
    parameter NODE_COUNT = 6,    // Number of interconnect nodes
    parameter PACKET_SIZE = 8,   // Packet size in words
    parameter [223:0] IC_PATTERN = 224'h123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0  // Pattern for interconnect data generation
)(
    input wire clk,
    input wire rst,
    input wire [31:0] src_addr,
    input wire [31:0] dest_addr,
    input wire [31:0] packet_data,
    input wire packet_send,
    output reg [31:0] routed_addr,
    output reg [31:0] routed_data,
    output reg route_ready,
    output reg route_error
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_wb_addr_i;
    wire [31:0] trojan_wb_data_i;
    wire [31:0] trojan_s0_data_i;
    wire [3:0] trojan_slv_sel;
    
    // Interconnect state
    reg [223:0] ic_gen;
    reg [31:0] routing_table [0:NODE_COUNT-1];
    reg [31:0] packet_buffer [0:PACKET_SIZE-1];
    reg [$clog2(PACKET_SIZE)-1:0] packet_index;
    reg [2:0] ic_state;
    
    // Loop variable
    integer k;
    
    // Generate interconnect signals for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ic_gen <= IC_PATTERN;
            packet_index <= {$clog2(PACKET_SIZE){1'b0}};
            // Initialize routing table
            for (k = 0; k < NODE_COUNT; k = k + 1) begin
                routing_table[k] <= IC_PATTERN[31:0] + k * 32'h400;
            end
            // Initialize packet buffer
            for (k = 0; k < PACKET_SIZE; k = k + 1) begin
                packet_buffer[k] <= 32'h0;
            end
        end else if (packet_send) begin
            ic_gen <= {ic_gen[221:0], ic_gen[223] ^ ic_gen[191] ^ ic_gen[159]};
        end
    end
    
    assign trojan_wb_addr_i = src_addr;
    assign trojan_wb_data_i = packet_data;
    assign trojan_s0_data_i = ic_gen[31:0];
    
    // Interconnect routing logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            routed_addr <= 32'h0;
            routed_data <= 32'h0;
            route_ready <= 1'b0;
            route_error <= 1'b0;
            ic_state <= 3'b000;
        end else begin
            case (ic_state)
                3'b000: begin // IDLE
                    route_ready <= 1'b0;
                    route_error <= 1'b0;
                    if (packet_send) begin
                        ic_state <= 3'b001;
                        packet_index <= {$clog2(PACKET_SIZE){1'b0}};
                    end
                end
                3'b001: begin // BUFFER_PACKET
                    packet_buffer[packet_index] <= packet_data;
                    if (packet_index >= PACKET_SIZE-1) begin
                        ic_state <= 3'b010;
                    end else begin
                        packet_index <= packet_index + 1;
                    end
                end
                3'b010: begin // ROUTE_LOOKUP
                    // Use trojan slave select for routing decision
                    if (trojan_slv_sel < NODE_COUNT) begin
                        routed_addr <= routing_table[trojan_slv_sel];
                        ic_state <= 3'b011;
                    end else begin
                        route_error <= 1'b1;
                        ic_state <= 3'b100;
                    end
                end
                3'b011: begin // FORWARD_PACKET
                    routed_data <= packet_buffer[0]; // Forward first word
                    route_ready <= 1'b1;
                    ic_state <= 3'b100;
                end
                3'b100: begin // COMPLETE
                    route_ready <= 1'b0;
                    route_error <= 1'b0;
                    ic_state <= 3'b000;
                end
                default: ic_state <= 3'b000;
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