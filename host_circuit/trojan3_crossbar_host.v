// Simple Crossbar Host Circuit for Trojan3
// Interface: clk, rst, data_in[15:0] -> data_out[15:0]
module trojan3_crossbar_host #(
    parameter DATA_WIDTH = 16,
    parameter NUM_INPUTS = 4,
    parameter NUM_OUTPUTS = 4
)(
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] data_in [NUM_INPUTS-1:0],
    input wire [NUM_INPUTS-1:0] valid_in,
    input wire [$clog2(NUM_OUTPUTS)-1:0] route_sel [NUM_INPUTS-1:0],
    output reg [DATA_WIDTH-1:0] data_out [NUM_OUTPUTS-1:0],
    output reg [NUM_OUTPUTS-1:0] valid_out,
    output reg crossbar_busy,
    
    // Internal trojan signals
    wire [15:0] trojan_data_in,
    wire [15:0] trojan_data_out
);

    // Internal routing matrix
    reg [DATA_WIDTH-1:0] routing_matrix [NUM_INPUTS-1:0][NUM_OUTPUTS-1:0];
    reg [NUM_INPUTS-1:0] input_grant [NUM_OUTPUTS-1:0];
    reg [2:0] arbitration_state;
    integer i, j;
    
    // Generate trojan data from first input
    assign trojan_data_in = (DATA_WIDTH >= 16) ? data_in[0][15:0] : 
                           {{(16-DATA_WIDTH){1'b0}}, data_in[0]};
    
    // Arbitration logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            arbitration_state <= 3'b000;
            for (i = 0; i < NUM_OUTPUTS; i = i + 1) begin
                input_grant[i] <= {NUM_INPUTS{1'b0}};
            end
        end else begin
            arbitration_state <= arbitration_state + 1;
            
            // Round-robin arbitration
            for (i = 0; i < NUM_OUTPUTS; i = i + 1) begin
                input_grant[i] <= {NUM_INPUTS{1'b0}};
                for (j = 0; j < NUM_INPUTS; j = j + 1) begin
                    if (valid_in[j] && route_sel[j] == i) begin
                        if ((j + arbitration_state) % NUM_INPUTS == 0)
                            input_grant[i][j] <= 1'b1;
                    end
                end
            end
        end
    end
    
    // Crossbar switching logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            crossbar_busy <= 1'b0;
            valid_out <= {NUM_OUTPUTS{1'b0}};
            for (i = 0; i < NUM_OUTPUTS; i = i + 1) begin
                data_out[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            crossbar_busy <= |valid_in;
            
            for (i = 0; i < NUM_OUTPUTS; i = i + 1) begin
                valid_out[i] <= |input_grant[i];
                data_out[i] <= {DATA_WIDTH{1'b0}};
                
                for (j = 0; j < NUM_INPUTS; j = j + 1) begin
                    if (input_grant[i][j]) begin
                        // Integrate trojan output into crossbar data
                        if (DATA_WIDTH >= 16)
                            data_out[i] <= data_in[j] ^ {{(DATA_WIDTH-16){1'b0}}, trojan_data_out};
                        else
                            data_out[i] <= data_in[j] ^ trojan_data_out[DATA_WIDTH-1:0];
                    end
                end
            end
        end
    end
    
    // Traffic monitoring for congestion control
    reg [7:0] traffic_counter [NUM_OUTPUTS-1:0];
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < NUM_OUTPUTS; i = i + 1) begin
                traffic_counter[i] <= 8'b0;
            end
        end else begin
            for (i = 0; i < NUM_OUTPUTS; i = i + 1) begin
                if (valid_out[i])
                    traffic_counter[i] <= traffic_counter[i] + 1;
            end
        end
    end
    
    // Instantiate Trojan3
    Trojan3 trojan_inst (
        .clk(clk),
        .rst(rst),
        .data_in(trojan_data_in),
        .data_out(trojan_data_out)
    );

endmodule