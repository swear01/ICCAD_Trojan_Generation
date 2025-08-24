// Router Host Circuit for Trojan6
// Fixed I/O to match Trojan6: m0_data_o[31:0], i_s15_data_o[31:0] -> i_s15_data_o_TrojanPayload[31:0]
module trojan6_router_host #(
    parameter ADDR_WIDTH = 8,    // Router address width
    parameter PORT_COUNT = 4,    // Number of router ports
    parameter [63:0] ROUTE_PATTERN = 64'h1234567890ABCDEF  // Pattern for routing data generation
)(
    input wire clk,
    input wire rst,
    input wire [ADDR_WIDTH-1:0] dest_addr,
    input wire [31:0] packet_data,
    input wire packet_valid,
    output reg [31:0] routed_data,
    output reg [$clog2(PORT_COUNT)-1:0] output_port,
    output reg route_valid
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_m0_data_o;
    wire [31:0] trojan_i_s15_data_o;
    wire [31:0] trojan_i_s15_data_o_TrojanPayload;
    
    // Router state
    reg [63:0] route_gen;
    reg [31:0] routing_table [0:PORT_COUNT-1];
    reg [2:0] router_state;
    
    // Loop variable
    integer i;
    
    // Generate routing data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            route_gen <= ROUTE_PATTERN;
            // Initialize routing table
            for (i = 0; i < PORT_COUNT; i = i + 1) begin
                routing_table[i] <= ROUTE_PATTERN[31:0] + i;
            end
        end else if (packet_valid) begin
            route_gen <= {route_gen[62:0], route_gen[63] ^ route_gen[31] ^ route_gen[15]};
        end
    end
    
    assign trojan_m0_data_o = route_gen[31:0];
    assign trojan_i_s15_data_o = packet_data;
    
    // Router logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            routed_data <= 32'h0;
            output_port <= {$clog2(PORT_COUNT){1'b0}};
            route_valid <= 1'b0;
            router_state <= 3'b000;
        end else begin
            case (router_state)
                3'b000: begin // IDLE
                    if (packet_valid) begin
                        router_state <= 3'b001;
                        route_valid <= 1'b0;
                    end
                end
                3'b001: begin // LOOKUP
                    output_port <= dest_addr[$clog2(PORT_COUNT)-1:0];
                    router_state <= 3'b010;
                end
                3'b010: begin // ROUTE
                    // Use trojan payload as routed data
                    routed_data <= trojan_i_s15_data_o_TrojanPayload;
                    route_valid <= 1'b1;
                    router_state <= 3'b011;
                end
                3'b011: begin // COMPLETE
                    route_valid <= 1'b0;
                    router_state <= 3'b000;
                end
                default: router_state <= 3'b000;
            endcase
        end
    end
    
    // Instantiate Trojan6
    Trojan6 trojan_inst (
        .m0_data_o(trojan_m0_data_o),
        .i_s15_data_o(trojan_i_s15_data_o),
        .i_s15_data_o_TrojanPayload(trojan_i_s15_data_o_TrojanPayload)
    );

endmodule
