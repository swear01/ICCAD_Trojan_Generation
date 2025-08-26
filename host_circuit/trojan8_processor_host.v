// Processor Host Circuit for Trojan8
// Interface: a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], sel[2:0] -> y[15:0]
module trojan8_processor_host #(
    parameter CACHE_LINES = 64,           // Number of cache lines
    parameter ALU_OPS = 8,                // Number of ALU operations
    parameter [63:0] PROC_PATTERN = 64'hFEDCBA9876543210  // Processor data pattern
)(
    input wire clk,
    input wire rst,
    input wire [31:0] instruction,
    input wire [4:0] reg_addr,
    input wire [31:0] reg_data,
    input wire reg_write,
    input wire proc_enable,
    output reg [31:0] result,
    output reg proc_ready
);

    // Trojan interface
    wire [7:0] trojan_a;
    wire [7:0] trojan_b;
    wire [7:0] trojan_c;
    wire [7:0] trojan_d;
    wire [7:0] trojan_e;
    wire [2:0] trojan_sel;
    wire [15:0] trojan_y;
    
    // Processor components
    reg [31:0] registers [0:31];
    reg [31:0] cache_data [0:63];
    reg [31:0] alu_result [0:7];
    reg [63:0] proc_gen;
    reg [3:0] proc_state;
    reg [6:0] cache_ptr;  // 7-bit to match CACHE_LINES parameter range
    reg [3:0] alu_op;     // Make it 4-bit to match ALU_OPS comparison
    
    integer i;
    
    // Generate processor data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            proc_gen <= PROC_PATTERN;
            proc_state <= 4'h0;
            cache_ptr <= 7'h0;
            alu_op <= 4'h0;
            result <= 32'h0;
            proc_ready <= 1'b0;
            
            for (i = 0; i < 32; i = i + 1) begin
                registers[i] <= PROC_PATTERN[31:0] + i;
            end
            for (i = 0; i < 64; i = i + 1) begin
                cache_data[i] <= 32'h0;
            end
            for (i = 0; i < 8; i = i + 1) begin
                alu_result[i] <= 32'h0;
            end
        end else if (proc_enable) begin
            proc_gen <= {proc_gen[62:0], proc_gen[63]};
            
            case (proc_state)
                4'h0: begin // FETCH
                    if (cache_ptr < CACHE_LINES) begin
                        cache_data[cache_ptr[5:0]] <= instruction ^ {16'h0, trojan_y}; // Use only 6 bits for array index
                        cache_ptr <= cache_ptr + 1;
                        proc_state <= 4'h1;
                    end else begin
                        cache_ptr <= 7'h0;
                        proc_state <= 4'h2;
                    end
                end
                4'h1: begin // DECODE
                    alu_op <= {1'b0, instruction[2:0]};  // Extend to 4-bit
                    proc_state <= 4'h2;
                end
                4'h2: begin // EXECUTE
                    if (alu_op < ALU_OPS) begin
                        alu_result[alu_op[2:0]] <= registers[reg_addr] + (reg_write ? reg_data : 32'h0);  // Use reg_write
                        alu_op <= alu_op + 1;
                    end else begin
                        proc_state <= 4'h3;
                    end
                end
                4'h3: begin // WRITEBACK
                    result <= alu_result[0] + alu_result[1] + alu_result[2] + alu_result[3];
                    proc_ready <= 1'b1;
                    proc_state <= 4'h0;
                end
                default: proc_state <= 4'h0;
            endcase
        end
    end
    
    // Connect trojan inputs
    assign trojan_a = proc_gen[7:0];
    assign trojan_b = cache_data[0][7:0];
    assign trojan_c = registers[0][7:0];
    assign trojan_d = instruction[7:0];
    assign trojan_e = {3'b000, reg_addr};
    assign trojan_sel = proc_state[2:0];
    
    // Instantiate Trojan8
    Trojan8 #(
        .MASK_00FF(16'h00FF),
        .MASK_0F(8'h0F),
        .MASK_F0F0(16'hF0F0)
    ) trojan_inst (
        .a(trojan_a),
        .b(trojan_b),
        .c(trojan_c),
        .d(trojan_d),
        .e(trojan_e),
        .sel(trojan_sel),
        .y(trojan_y)
    );

endmodule
