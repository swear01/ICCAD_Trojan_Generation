module Trojan6 #(
    // Match Trojan6 non-I/O tunables
    parameter [31:0] TRIGGER_STATE_1 = 32'h00000000,
    parameter [31:0] TRIGGER_STATE_2 = 32'h354A7B6C,
    parameter [31:0] TRIGGER_STATE_3 = 32'hEAAAD8FF,
    parameter [31:0] TRIGGER_STATE_4 = 32'h0AAA5C5C,
    parameter [1:0]  PAYLOAD_BITS   = 2'b11
)(
    input  wire [31:0] m0_data_o,
    input  wire [31:0] i_s15_data_o,
    output wire [31:0] i_s15_data_o_TrojanPayload 
);

    // clean version - pass-through
    assign i_s15_data_o_TrojanPayload = i_s15_data_o;

endmodule