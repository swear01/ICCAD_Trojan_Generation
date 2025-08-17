module Trojan6 #(
    parameter DATA_WIDTH = 32,
    parameter TRIGGER_STATE_1 = 32'h00000000,
    parameter TRIGGER_STATE_2 = 32'h354A7B6C,
    parameter TRIGGER_STATE_3 = 32'hEAAAD8FF,
    parameter TRIGGER_STATE_4 = 32'h0AAA5C5C,
    parameter PAYLOAD_BITS = 2'b11
)(
    input wire [DATA_WIDTH-1:0] m0_data_o,
    input wire [DATA_WIDTH-1:0] i_s15_data_o,
    output wire [DATA_WIDTH-1:0] i_s15_data_o_TrojanPayload 
);

    wire [1:0] Trojanstate; // Dummy state for compatibility

    assign Trojanstate = 2'b00; // Always default state in clean version

    assign i_s15_data_o_TrojanPayload = i_s15_data_o; // Clean pass-through

endmodule