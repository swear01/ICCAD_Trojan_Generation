// FSM Host Circuit for Trojan1
// Fixed I/O to match Trojan1: clk, rst, r1 -> trigger
module trojan1_fsm_host #(
    parameter DATA_WIDTH = 8,    // State and data width
    parameter [7:0] INIT_SEED = 8'hA5  // Initial seed for r1 generation
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] data_in,
    input wire enable,
    output reg [DATA_WIDTH-1:0] state_out,
    output reg [DATA_WIDTH-1:0] data_out,
    output reg valid
);

    // Trojan interface (fixed width)
    wire trojan_r1;
    wire trojan_trigger;
    
    // Internal FSM states
    reg [2:0] current_state, next_state;
    reg [DATA_WIDTH-1:0] data_reg;
    reg [7:0] r1_generator;
    
    // State encoding
    localparam IDLE = 3'b000;
    localparam PROC1 = 3'b001;
    localparam PROC2 = 3'b010;
    localparam PROC3 = 3'b011;
    localparam OUTPUT = 3'b100;
    
    // R1 signal generation for trojan
    always @(posedge clk or posedge rst) begin
        if (rst)
            r1_generator <= INIT_SEED;
        else if (enable)
            r1_generator <= {r1_generator[6:0], r1_generator[7] ^ r1_generator[3]};
    end
    
    assign trojan_r1 = r1_generator[0];
    
    // FSM state logic
    always @(posedge clk or posedge rst) begin
        if (rst)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end
    
    // Next state logic
    always @(*) begin
        case (current_state)
            IDLE: next_state = enable ? PROC1 : IDLE;
            PROC1: next_state = enable ? PROC2 : IDLE;  // Allow early exit
            PROC2: next_state = enable ? PROC3 : IDLE;  // Allow early exit
            PROC3: next_state = enable ? OUTPUT : IDLE; // Allow early exit
            OUTPUT: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end
    
    // Data processing
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_reg <= {DATA_WIDTH{1'b0}};
            state_out <= {DATA_WIDTH{1'b0}};
            data_out <= {DATA_WIDTH{1'b0}};
            valid <= 1'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    data_reg <= data_in;
                    valid <= 1'b0;
                end
                PROC1: begin
                    data_reg <= data_reg + 1;
                end
                PROC2: begin
                    // Simple alternating pattern XOR
                    data_reg <= data_reg ^ ({DATA_WIDTH{1'b1}} >> 1);
                end
                PROC3: begin
                    data_reg <= data_reg << 1;
                end
                OUTPUT: begin
                    // Mix output with trojan trigger (proper width handling)
                    data_out <= data_reg ^ {DATA_WIDTH{trojan_trigger}};
                    // Safe state output assignment (assume DATA_WIDTH >= 3)
                    state_out <= {{(DATA_WIDTH-3){1'b0}}, current_state};
                    valid <= 1'b1;
                end
                default: begin
                    // Default case for unknown states
                    valid <= 1'b0;
                end
            endcase
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
