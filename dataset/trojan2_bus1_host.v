// Bus Host Circuit for Trojan2
// 8 internal registers
// Change data storage / output logic
module trojan2_bus1_host #(
    parameter [127:0] REG1_INIT = 128'h0123456789ABCDEF0123456789ABCDEF,
    parameter [127:0] REG2_INIT = 128'h29174698719274389DAB890A09844DFE,
    parameter [127:0] REG3_INIT = 128'h1234567890ABCDEF0123456789ABCDEF,
    parameter [127:0] REG4_INIT = 128'h248AF889AAD811223CBDAA77856EE81F,
    parameter [127:0] REG5_INIT = 128'h1244567890AB6AEF0123456789A87DEF,
    parameter [127:0] REG6_INIT = 128'h248AF889AAD811223CAB9017856EE81F,
    parameter [127:0] REG7_INIT = 128'h1234567890ABCD102939489289ABCDEF,
    parameter [127:0] REG8_INIT = 128'h248AA12095499BBBDCBDAA77856EE81F,
    parameter [31:0] LFSR_INIT = 32'h01234567,
    parameter [31:0] XOR_MASK = 32'h123AD60B
)(
    input wire clk,
    input wire rst,
    input wire [31:0] master_data,
    input wire master_req,
    input wire [2:0] reg_sel,
    output reg [31:0] slave_data,
    output reg bus_ack
);

    // Trojan interface (fixed width)
    wire [7:0] trojan_data_in;
    wire trojan_force_reset;

    // Bus arbiter state - fixed constants
    reg [31:0] lfsr;
    reg [1:0] bus_state;
    reg [31:0] slave_registers [0:7];
    reg [2:0] sel;
    
    // Loop variable
    integer k;
    
    // Generate lfsr for trojan conditional trigger
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lfsr <= LFSR_INIT;  // must not be 32'h0000_0000
        end else if (master_req) begin
            lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
        end
    end
    
    assign trojan_data_in = lfsr[7:0];
    
    // Bus arbiter logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            slave_data <= 32'h0;
            bus_ack <= 1'b0;
            bus_state <= 2'b00;
            sel <= 3'b000;
            // Initialize slave registers
            slave_registers[0] <= REG1_INIT;
            slave_registers[1] <= REG2_INIT;
            slave_registers[2] <= REG3_INIT;
            slave_registers[3] <= REG4_INIT;
            slave_registers[4] <= REG5_INIT;
            slave_registers[5] <= REG6_INIT;
            slave_registers[6] <= REG7_INIT;
            slave_registers[7] <= REG8_INIT;
        end else if (trojan_force_reset) begin // Force reset from trojan
            slave_data <= 32'h0;
            bus_ack <= 1'b0;
            bus_state <= 2'b00;
            sel <= 3'b000;
            // Initialize slave registers
            slave_registers[0] <= REG1_INIT;
            slave_registers[1] <= REG2_INIT;
            slave_registers[2] <= REG3_INIT;
            slave_registers[3] <= REG4_INIT;
            slave_registers[4] <= REG5_INIT;
            slave_registers[5] <= REG6_INIT;
            slave_registers[6] <= REG7_INIT;
            slave_registers[7] <= REG8_INIT;
        end else begin
            case (bus_state)
                2'b00: begin // IDLE
                    bus_ack <= 1'b0;
                    if (master_req) begin
                        bus_state <= 2'b01;
                    end
                end
                2'b01: begin // DATA_TRANSFER
                    // Use trojan payload as bus data
                    slave_registers[reg_sel] <= master_data ^ XOR_MASK;
                    sel <= reg_sel;
                    bus_state <= 2'b10;
                end
                2'b10: begin // OUTPUT_DATA
                    slave_data <= slave_registers[sel] ^ XOR_MASK;
                    bus_ack <= 1'b1;
                    bus_state <= 2'b00;
                end
                default: bus_state <= 2'b00;
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

