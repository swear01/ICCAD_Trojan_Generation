// Network Host Circuit for Trojan7
// Fixed I/O to match Trojan7: wb_addr_i[31:0], wb_data_i[31:0], s0_data_i[31:0] -> slv_sel[3:0]
module trojan7_network_host #(
    parameter PORT_COUNT = 8,         // Number of network ports
    parameter PACKET_SIZE = 64,       // Maximum packet size in bytes
    parameter [191:0] NET_PATTERN = 192'h123456789ABCDEF0FEDCBA9876543210DEADBEEFCAFEBABE  // Network data pattern
)(
    input wire clk,
    input wire rst,
    input wire [7:0] rx_data,
    input wire rx_valid,
    input wire [2:0] rx_port,
    input wire tx_ready,
    output reg [7:0] tx_data,
    output reg tx_valid,
    output reg [2:0] tx_port,
    output reg packet_ready
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_wb_addr_i;
    wire [31:0] trojan_wb_data_i;
    wire [31:0] trojan_s0_data_i;
    wire [3:0] trojan_slv_sel;
    
    // Network state - fixed constants
    localparam MAX_PORTS = 8;
    localparam BUFFER_SIZE = 128;
    
    reg [7:0] rx_buffer [0:127];      // Fixed buffer size
    reg [7:0] tx_buffer [0:127];      // Fixed buffer size
    reg [7:0] routing_table [0:7];    // Fixed routing table
    reg [191:0] net_gen;
    reg [4:0] net_state;
    reg [6:0] rx_ptr, tx_ptr;
    reg [7:0] packet_length;
    reg [2:0] dest_port;
    
    // Loop variable
    integer n;
    
    // Generate network data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            net_gen <= NET_PATTERN;
            rx_ptr <= 7'h0;
            tx_ptr <= 7'h0;
            // Initialize buffers using blocking assignment
            for (n = 0; n < 128; n = n + 1) begin
                rx_buffer[n] = 8'h0;
                tx_buffer[n] = 8'h0;
            end
            // Initialize routing table
            for (n = 0; n < 8; n = n + 1) begin
                routing_table[n] <= NET_PATTERN[7:0] + n[7:0];
            end
        end else if (rx_valid || tx_ready) begin
            net_gen <= {net_gen[190:0], net_gen[191] ^ net_gen[159] ^ net_gen[127] ^ net_gen[95]};
        end
    end
    
    assign trojan_wb_addr_i = {24'h0, packet_length};
    assign trojan_wb_data_i = net_gen[31:0];
    assign trojan_s0_data_i = {24'h0, rx_data};
    
    // Network packet processing
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_data <= 8'h0;
            tx_valid <= 1'b0;
            tx_port <= 3'h0;
            packet_ready <= 1'b0;
            net_state <= 5'h0;
            packet_length <= 8'h0;
            dest_port <= 3'h0;
        end else begin
            case (net_state)
                5'h0: begin // IDLE
                    packet_ready <= 1'b0;
                    tx_valid <= 1'b0;
                    if (rx_valid) begin
                        rx_buffer[rx_ptr] <= rx_data;
                        if (rx_ptr == 7'h0) begin
                            packet_length <= rx_data; // First byte is length
                        end else if (rx_ptr == 7'h1) begin
                            dest_port <= rx_data[2:0]; // Second byte contains dest port
                        end
                        rx_ptr <= rx_ptr + 1;
                        net_state <= 5'h1;
                    end
                end
                5'h1: begin // RECEIVE
                    if (rx_valid) begin
                        rx_buffer[rx_ptr] <= rx_data;
                        rx_ptr <= rx_ptr + 1;
                        if ({{1{1'b0}}, rx_ptr} >= packet_length) begin
                            net_state <= 5'h2;
                        end
                    end else if ({{1{1'b0}}, rx_ptr} >= packet_length) begin
                        net_state <= 5'h2;
                    end
                end
                5'h2: begin // ROUTE
                    // Simple routing based on destination
                    tx_port <= routing_table[dest_port][2:0];
                    // Copy packet to tx buffer
                    for (n = 0; n < 64; n = n + 1) begin
                        tx_buffer[n] <= (n < packet_length) ? rx_buffer[n] : 8'h0;
                    end
                    tx_ptr <= 7'h0;
                    net_state <= 5'h3;
                end
                5'h3: begin // TRANSMIT
                    if (tx_ready && {{1{1'b0}}, tx_ptr} < packet_length) begin
                        tx_data <= tx_buffer[tx_ptr] ^ {4'h0, trojan_slv_sel};
                        tx_valid <= 1'b1;
                        tx_ptr <= tx_ptr + 1;
                    end else if ({{1{1'b0}}, tx_ptr} >= packet_length) begin
                        tx_valid <= 1'b0;
                        packet_ready <= 1'b1;
                        rx_ptr <= 7'h0;
                        net_state <= 5'h0;
                    end else begin
                        tx_valid <= 1'b0;
                    end
                end
                default: net_state <= 5'h0;
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
