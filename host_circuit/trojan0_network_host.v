// Network Host Circuit for Trojan0
// Fixed I/O to match Trojan0: key[127:0] -> load[63:0]
module trojan0_network_host #(
    parameter PACKET_SIZE = 64,  // Network packet size in bytes
    parameter BUFFER_DEPTH = 16, // Packet buffer depth
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

    // Trojan interface (fixed width)
    wire [127:0] trojan_key;
    wire [63:0] trojan_load;
    
    // Network state
    reg [PACKET_SIZE*8-1:0] packet_buffer [0:BUFFER_DEPTH-1];
    reg [127:0] key_generator;
    reg [3:0] buffer_head, buffer_tail;
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
        buffer_full = (packet_count == 4'(BUFFER_DEPTH));
        buffer_empty = (packet_count == 4'h0);
    end
    
    // Network processing state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            buffer_head <= 4'h0;
            buffer_tail <= 4'h0;
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
                        route_error <= 1'b1;
                    end
                end
                3'b001: begin // RECEIVE_PACKET
                    packet_buffer[buffer_tail] <= packet_in;
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
                    packet_out <= packet_buffer[buffer_head] ^ {{PACKET_SIZE*8-64{1'b0}}, trojan_load};
                    buffer_head <= buffer_head + 1;
                    packet_count <= packet_count - 1;
                    packet_ready <= 1'b1;
                    network_state <= 3'b000;
                end
                default: network_state <= 3'b000;
            endcase
        end
    end
    
    // Initialize packet buffer
    integer i;
    always @(posedge rst) begin
        if (rst) begin
            for (i = 0; i < BUFFER_DEPTH; i = i + 1) begin
                packet_buffer[i] <= {PACKET_SIZE*8{1'b0}};
            end
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
