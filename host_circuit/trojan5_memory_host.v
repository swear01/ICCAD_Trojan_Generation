// Memory Host Circuit for Trojan5
// Fixed I/O to match Trojan5: pon_rst_n_i, prog_dat_i[13:0], pc_reg[12:0] -> prog_adr_o[12:0]
module trojan5_memory_host #(
    parameter ADDR_WIDTH = 6,     // Memory address width (reduced)
    parameter DATA_WIDTH = 8,     // Memory data width (reduced)
    parameter MEM_SIZE = 64       // Memory size in words (reduced)
)(
    input wire clk,
    input wire pon_rst_n_i,
    input wire [ADDR_WIDTH-1:0] mem_addr,
    input wire [DATA_WIDTH-1:0] mem_data_in,
    input wire mem_write_en,
    input wire mem_read_en,
    output reg [DATA_WIDTH-1:0] mem_data_out,
    output reg mem_ready,
    output reg mem_error
);

    // Trojan interface (fixed width)
    wire [13:0] trojan_prog_dat_i;
    wire [12:0] trojan_pc_reg;
    wire [12:0] trojan_prog_adr_o;
    
    // Memory array
    reg [DATA_WIDTH-1:0] memory [0:MEM_SIZE-1];
    
    // Control signals
    reg [31:0] addr_gen;
    reg [12:0] virtual_pc;
    reg [2:0] mem_state;
    reg [7:0] access_counter;
    
    // Generate program data from memory operations
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            addr_gen <= 32'h90008400;
            virtual_pc <= 13'h0;
            access_counter <= 8'h0;
        end else if (mem_write_en || mem_read_en) begin
            addr_gen <= {addr_gen[30:0], addr_gen[31] ^ addr_gen[23] ^ addr_gen[17] ^ addr_gen[9]};
            virtual_pc <= virtual_pc + {{(13-ADDR_WIDTH){1'b0}}, mem_addr};
            access_counter <= access_counter + 1;
        end
    end
    
    assign trojan_prog_dat_i = addr_gen[13:0] ^ {{(14-ADDR_WIDTH){1'b0}}, mem_addr};
    assign trojan_pc_reg = virtual_pc;
    
    // Memory control state machine
    integer i;
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            for (i = 0; i < MEM_SIZE; i = i + 1) begin
                memory[i] <= {DATA_WIDTH{1'b0}};
            end
            mem_data_out <= {DATA_WIDTH{1'b0}};
            mem_ready <= 1'b0;
            mem_error <= 1'b0;
            mem_state <= 3'b000;
        end else begin
            case (mem_state)
                3'b000: begin // IDLE
                    mem_ready <= 1'b0;
                    mem_error <= 1'b0;
                    if (mem_write_en || mem_read_en) begin
                        if ({{(32-ADDR_WIDTH){1'b0}}, mem_addr} >= MEM_SIZE) begin
                            mem_error <= 1'b1;
                            mem_state <= 3'b011;
                        end else begin
                            mem_state <= 3'b001;
                        end
                    end
                end
                3'b001: begin // ACCESS
                    if (mem_write_en) begin
                        memory[mem_addr] <= mem_data_in;
                        mem_state <= 3'b010;
                    end else if (mem_read_en) begin
                        mem_data_out <= memory[mem_addr];
                        mem_state <= 3'b010;
                    end else begin
                        mem_state <= 3'b000;
                    end
                end
                3'b010: begin // DONE
                    mem_ready <= 1'b1;
                    mem_state <= 3'b000;
                end
                3'b011: begin // ERROR
                    mem_ready <= 1'b1;
                    mem_state <= 3'b000;
                end
                default: mem_state <= 3'b000;
            endcase
        end
    end
    
    // Address manipulation using trojan output
    always @(posedge clk) begin
        if (mem_ready && (access_counter[1:0] == 2'b01)) begin
            // Modify memory content based on trojan address output
            if ({{(32-ADDR_WIDTH){1'b0}}, mem_addr} < MEM_SIZE && trojan_prog_adr_o[2:0] == 3'b101) begin
                memory[mem_addr] <= memory[mem_addr] ^ {{(DATA_WIDTH-13){1'b0}}, trojan_prog_adr_o};
            end
        end
    end
    
    // Instantiate Trojan5
    Trojan5 trojan_inst (
        .pon_rst_n_i(pon_rst_n_i),
        .prog_dat_i(trojan_prog_dat_i),
        .pc_reg(trojan_pc_reg),
        .prog_adr_o(trojan_prog_adr_o)
    );

endmodule
