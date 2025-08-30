// Network Host Circuit for Trojan0
// Fixed I/O to match Trojan0: key[127:0] -> load[63:0]
module trojan0_network_host #(
    parameter [127:0] KEY_INIT = 128'h123456789ABCDEF0FEDCBA0987654321  // Network key seed
)(
    input wire clk,
    input wire rst,
    input wire [PACKET_SIZE*8-1:0] packet_in,
    input wire packet_valid,
    input wire [3:0] dest_addr,
    output reg [PACKET_SIZE*8-1:0] packet_out,
    output reg packet_ready,
    output reg route_error
);

    // Sizing parameters (converted from parameter to localparam)
    localparam PACKET_SIZE = 8;   // Network packet size in bytes (reduced for synthesis)
    localparam BUFFER_DEPTH = 4;  // Packet buffer depth (reduced for synthesis)

    // Trojan interface (fixed width)
    wire [127:0] trojan_key;
    wire [63:0] trojan_load;
    
    // Network state
    reg [PACKET_SIZE*8-1:0] packet_buffer_0, packet_buffer_1, packet_buffer_2, packet_buffer_3;
    reg [127:0] key_generator;
    reg [1:0] buffer_head, buffer_tail;
    reg [3:0] packet_count;
    reg [2:0] network_state;
    reg buffer_full, buffer_empty;
    
    // Key generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst)
            key_generator <= KEY_INIT;
        else if (packet_valid)
            key_generator <= {key_generator[123:0], key_generator[127:124] ^ dest_addr};
    end
    
    assign trojan_key = key_generator;
    
    // Buffer management
    always @(*) begin
        buffer_full = (packet_count == BUFFER_DEPTH[3:0]);
        buffer_empty = (packet_count == 4'h0);
    end
    
    // Network processing state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            buffer_head <= 2'b00;
            buffer_tail <= 2'b00;
            packet_count <= 4'h0;
            network_state <= 3'b000;
            packet_ready <= 1'b0;
            route_error <= 1'b0;
        end else begin
            case (network_state)
                3'b000: begin // IDLE
                    packet_ready <= 1'b0;
                    route_error <= 1'b0;
                    if (packet_valid && !buffer_full) begin
                        network_state <= 3'b001;
                    end else if (packet_valid && buffer_full) begin
                        route_error <= 1'b1; // Buffer overflow error
                    end
                end
                3'b001: begin // RECEIVE_PACKET
                    case (buffer_tail)
                        2'b00: packet_buffer_0 <= packet_in;
                        2'b01: packet_buffer_1 <= packet_in;
                        2'b10: packet_buffer_2 <= packet_in;
                        2'b11: packet_buffer_3 <= packet_in;
                    endcase
                    buffer_tail <= buffer_tail + 1;
                    packet_count <= packet_count + 1;
                    network_state <= 3'b010;
                end
                3'b010: begin // PROCESS_PACKET
                    if (!buffer_empty) begin
                        network_state <= 3'b011;
                    end else begin
                        network_state <= 3'b000;
                    end
                end
                3'b011: begin // SEND_PACKET
                    case (buffer_head)
                        2'b00: packet_out <= packet_buffer_0 ^ (PACKET_SIZE*8)'(trojan_load);
                        2'b01: packet_out <= packet_buffer_1 ^ (PACKET_SIZE*8)'(trojan_load);
                        2'b10: packet_out <= packet_buffer_2 ^ (PACKET_SIZE*8)'(trojan_load);
                        2'b11: packet_out <= packet_buffer_3 ^ (PACKET_SIZE*8)'(trojan_load);
                    endcase
                    buffer_head <= buffer_head + 1;
                    packet_count <= packet_count - 1;
                    packet_ready <= 1'b1;
                    network_state <= 3'b000;
                end
                default: network_state <= 3'b000;
            endcase
        end
    end
    
    
    // Instantiate Trojan0
    Trojan0 trojan_inst (
        .clk(clk),
        .rst(rst),
        .key(trojan_key),
        .load(trojan_load)
    );

endmodule
