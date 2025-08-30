// Counter Host Circuit for Trojan0
// Fixed I/O to match Trojan0: key[127:0] -> load[63:0]
module trojan0_counter_host #(
    parameter [127:0] KEY_INIT = 128'h13579BDF02468ACE13579BDF02468ACE  // Key generator seed
)(
    input wire clk,
    input wire rst,
    input wire enable,
    output reg [COUNT_WIDTH-1:0] count_out,
    output reg overflow,
    output reg pulse_out
);

    // Sizing parameters (converted from parameter to localparam)
    localparam COUNT_WIDTH = 12;  // Counter width
    localparam PERIOD = 100;      // Count period

    // Internal counter
    reg [COUNT_WIDTH-1:0] counter;
    reg [COUNT_WIDTH-1:0] period_counter;
    reg [127:0] key_generator;
    
    // Trojan interface (fixed width)
    wire [127:0] trojan_key;
    wire [63:0] trojan_load;
    
    // Key generation based on counter values
    always @(posedge clk or posedge rst) begin
        if (rst)
            key_generator <= KEY_INIT;
        else if (enable)
            key_generator <= {key_generator[119:0], key_generator[127:120] ^ counter[7:0]};
    end
    
    // Main counter logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= {COUNT_WIDTH{1'b0}};
            period_counter <= {COUNT_WIDTH{1'b0}};
            overflow <= 1'b0;
            pulse_out <= 1'b0;
        end else if (enable) begin
            counter <= counter + 1;
            period_counter <= period_counter + 1;
            
            // Generate overflow
            overflow <= (counter == {COUNT_WIDTH{1'b1}});
            
            // Generate periodic pulse
            if (period_counter >= PERIOD-1) begin
                pulse_out <= 1'b1;
                period_counter <= {COUNT_WIDTH{1'b0}};
            end else begin
                pulse_out <= 1'b0;
            end
        end
    end
    
    // Output with trojan load mixing
    always @(posedge clk or posedge rst) begin
        if (rst)
            count_out <= {COUNT_WIDTH{1'b0}};
        else
            count_out <= counter ^ trojan_load[COUNT_WIDTH-1:0];
    end
    
    // Connect to trojan (fixed width)
    assign trojan_key = key_generator;
    
    Trojan0 trojan_inst (
        .clk(clk),
        .rst(rst),
        .key(trojan_key),
        .load(trojan_load)
    );

endmodule

