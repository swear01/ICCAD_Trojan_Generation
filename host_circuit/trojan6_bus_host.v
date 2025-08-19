// Bus Host Circuit for Trojan6
// Fixed I/O to match Trojan6: m0_data_o[31:0], i_s15_data_o[31:0] -> i_s15_data_o_TrojanPayload[31:0]
module trojan6_bus_host #(
    parameter MASTER_COUNT = 3,  // Number of bus masters
    parameter SLAVE_COUNT = 4,   // Number of bus slaves
    parameter [127:0] BUS_PATTERN = 128'h0123456789ABCDEF0123456789ABCDEF  // Pattern for bus data generation
)(
    input wire clk,
    input wire rst,
    input wire [31:0] master_addr,
    input wire [31:0] master_data,
    input wire master_req,
    input wire [$clog2(SLAVE_COUNT)-1:0] slave_sel,
    output reg [31:0] slave_data,
    output reg bus_ack,
    output reg bus_err
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_m0_data_o;
    wire [31:0] trojan_i_s15_data_o;
    wire [31:0] trojan_i_s15_data_o_TrojanPayload;
    
    // Bus arbiter state
    reg [127:0] bus_gen;
    reg [$clog2(MASTER_COUNT)-1:0] grant_master;
    reg [2:0] bus_state;
    reg [31:0] slave_registers [0:SLAVE_COUNT-1];
    
    // Loop variable
    integer k;
    
    // Generate bus data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            bus_gen <= BUS_PATTERN;
            grant_master <= {$clog2(MASTER_COUNT){1'b0}};
            // Initialize slave registers
            for (k = 0; k < SLAVE_COUNT; k = k + 1) begin
                slave_registers[k] <= BUS_PATTERN[31:0] + k * 32'h1000;
            end
        end else if (master_req) begin
            bus_gen <= {bus_gen[125:0], bus_gen[127] ^ bus_gen[95] ^ bus_gen[63]};
            grant_master <= grant_master + 1;
        end
    end
    
    assign trojan_m0_data_o = bus_gen[31:0];
    assign trojan_i_s15_data_o = master_data;
    
    // Bus arbiter logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            slave_data <= 32'h0;
            bus_ack <= 1'b0;
            bus_err <= 1'b0;
            bus_state <= 3'b000;
        end else begin
            case (bus_state)
                3'b000: begin // IDLE
                    bus_ack <= 1'b0;
                    bus_err <= 1'b0;
                    if (master_req) begin
                        bus_state <= 3'b001;
                    end
                end
                3'b001: begin // ARBITRATION
                    bus_state <= 3'b010;
                end
                3'b010: begin // ADDRESS_DECODE
                    if (slave_sel < SLAVE_COUNT) begin
                        bus_state <= 3'b011;
                    end else begin
                        bus_err <= 1'b1;
                        bus_state <= 3'b100;
                    end
                end
                3'b011: begin // DATA_TRANSFER
                    // Use trojan payload as bus data
                    slave_registers[slave_sel] <= trojan_i_s15_data_o_TrojanPayload;
                    slave_data <= slave_registers[slave_sel];
                    bus_ack <= 1'b1;
                    bus_state <= 3'b100;
                end
                3'b100: begin // COMPLETE
                    bus_ack <= 1'b0;
                    bus_err <= 1'b0;
                    bus_state <= 3'b000;
                end
                default: bus_state <= 3'b000;
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