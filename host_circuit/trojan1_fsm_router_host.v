// FSM Router Host Circuit for Trojan1
// Interface: clk, rst, r1 -> trigger (both single bit)
module trojan1_fsm_router_host #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 8,
    parameter NUM_PORTS = 4,
    parameter TRIGGER_WIDTH = 1
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] packet_in,
    input wire [ADDR_WIDTH-1:0] dest_addr,
    input wire packet_valid,
    input wire [NUM_PORTS-1:0] port_ready,
    output reg [DATA_WIDTH-1:0] packet_out [NUM_PORTS-1:0],
    output reg [NUM_PORTS-1:0] port_valid,
    output reg busy,
    output reg [1:0] router_state,
    
    // Internal trojan signals
    wire trojan_r1,
    wire trojan_trigger
);

    // FSM States
    localparam IDLE = 2'b00;
    localparam DECODE = 2'b01;
    localparam ROUTE = 2'b10;
    localparam WAIT_ACK = 2'b11;
    
    // Internal registers
    reg [DATA_WIDTH-1:0] packet_buffer;
    reg [ADDR_WIDTH-1:0] target_port;
    reg [3:0] decode_counter;
    reg [7:0] routing_table [NUM_PORTS-1:0];
    reg r1_signal;
    
    // Initialize routing table
    integer i;
    initial begin
        for (i = 0; i < NUM_PORTS; i = i + 1) begin
            routing_table[i] = i * (256 / NUM_PORTS);
        end
    end
    
    // Generate r1 signal for trojan based on packet activity
    always @(posedge clk or posedge rst) begin
        if (rst)
            r1_signal <= 1'b0;
        else
            r1_signal <= packet_valid && (dest_addr[1:0] == 2'b11);
    end
    
    assign trojan_r1 = r1_signal;
    
    // Address decoder
    always @(*) begin
        if (ADDR_WIDTH >= 8) begin
            target_port = dest_addr[7:6];
        end else begin
            target_port = dest_addr[ADDR_WIDTH-1:ADDR_WIDTH-2];
        end
        if (target_port >= NUM_PORTS)
            target_port = 0;
    end
    
    // Main FSM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            router_state <= IDLE;
            packet_buffer <= {DATA_WIDTH{1'b0}};
            decode_counter <= 4'b0;
            busy <= 1'b0;
            port_valid <= {NUM_PORTS{1'b0}};
            for (i = 0; i < NUM_PORTS; i = i + 1) begin
                packet_out[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            case (router_state)
                IDLE: begin
                    busy <= 1'b0;
                    port_valid <= {NUM_PORTS{1'b0}};
                    if (packet_valid) begin
                        packet_buffer <= packet_in;
                        router_state <= DECODE;
                        busy <= 1'b1;
                        decode_counter <= 4'b0;
                    end
                end
                
                DECODE: begin
                    decode_counter <= decode_counter + 1;
                    if (decode_counter >= 3) begin
                        router_state <= ROUTE;
                    end
                end
                
                ROUTE: begin
                    if (port_ready[target_port]) begin
                        // Integrate trojan trigger into packet routing
                        if (trojan_trigger)
                            packet_out[target_port] <= packet_buffer ^ {{(DATA_WIDTH-8){1'b0}}, 8'hFF};
                        else
                            packet_out[target_port] <= packet_buffer ^ 
                                {{(DATA_WIDTH-ADDR_WIDTH){1'b0}}, dest_addr};
                        port_valid[target_port] <= 1'b1;
                        router_state <= WAIT_ACK;
                    end
                end
                
                WAIT_ACK: begin
                    if (!port_ready[target_port]) begin
                        port_valid <= {NUM_PORTS{1'b0}};
                        router_state <= IDLE;
                    end
                end
                
                default: router_state <= IDLE;
            endcase
        end
    end
    
    // Update routing table dynamically with trojan influence
    always @(posedge clk) begin
        if (!rst && router_state == ROUTE) begin
            if (trojan_trigger)
                routing_table[target_port] <= routing_table[target_port] + 2;
            else
                routing_table[target_port] <= routing_table[target_port] + 1;
        end
    end
    
    // Instantiate Trojan1
    Trojan1 trojan_inst (
        .clk(clk),
        .rst(rst),
        .r1(trojan_r1),
        .trigger(trojan_trigger)
    );

endmodule