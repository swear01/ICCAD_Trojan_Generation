// Wishbone Host Circuit for Trojan7
// Fixed I/O to match Trojan7: wb_addr_i[31:0], wb_data_i[31:0], s0_data_i[31:0] -> slv_sel[3:0]
module trojan7_wishbone_host #(
    parameter SLAVE_COUNT = 8,   // Number of wishbone slaves
    parameter TIMEOUT_CYCLES = 16,  // Timeout for transactions
    parameter [191:0] WB_PATTERN = 192'h123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0  // Pattern for wishbone data generation
)(
    input wire clk,
    input wire rst,
    input wire [31:0] wb_master_adr,
    input wire [31:0] wb_master_dat_w,
    input wire wb_master_cyc,
    input wire wb_master_stb,
    input wire wb_master_we,
    output reg [31:0] wb_master_dat_r,
    output reg wb_master_ack,
    output reg wb_master_err
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_wb_addr_i;
    wire [31:0] trojan_wb_data_i;
    wire [31:0] trojan_s0_data_i;
    wire [3:0] trojan_slv_sel;
    
    // Wishbone arbiter state
    reg [191:0] wb_gen;
    reg [31:0] slave_data [0:SLAVE_COUNT-1];
    reg [$clog2(TIMEOUT_CYCLES)-1:0] timeout_counter;
    reg [2:0] wb_state;
    
    // Loop variable
    integer j;
    
    // Generate wishbone signals for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wb_gen <= WB_PATTERN;
            timeout_counter <= {$clog2(TIMEOUT_CYCLES){1'b0}};
            // Initialize slave data
            for (j = 0; j < SLAVE_COUNT; j = j + 1) begin
                slave_data[j] <= WB_PATTERN[31:0] + j * 32'h200;
            end
        end else if (wb_master_cyc && wb_master_stb) begin
            wb_gen <= {wb_gen[189:0], wb_gen[191] ^ wb_gen[159] ^ wb_gen[127]};
            timeout_counter <= timeout_counter + 1;
        end else begin
            timeout_counter <= {$clog2(TIMEOUT_CYCLES){1'b0}};
        end
    end
    
    assign trojan_wb_addr_i = wb_master_adr;
    assign trojan_wb_data_i = wb_master_dat_w;
    assign trojan_s0_data_i = wb_gen[31:0];
    
    // Wishbone bus controller
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wb_master_dat_r <= 32'h0;
            wb_master_ack <= 1'b0;
            wb_master_err <= 1'b0;
            wb_state <= 3'b000;
        end else begin
            case (wb_state)
                3'b000: begin // IDLE
                    wb_master_ack <= 1'b0;
                    wb_master_err <= 1'b0;
                    if (wb_master_cyc && wb_master_stb) begin
                        wb_state <= 3'b001;
                    end
                end
                3'b001: begin // DECODE
                    wb_state <= 3'b010;
                end
                3'b010: begin // ACCESS
                    // Use trojan slave select for addressing
                    if (trojan_slv_sel < SLAVE_COUNT) begin
                        if (wb_master_we) begin
                            // Write operation
                            slave_data[trojan_slv_sel] <= wb_master_dat_w;
                        end else begin
                            // Read operation
                            wb_master_dat_r <= slave_data[trojan_slv_sel];
                        end
                        wb_master_ack <= 1'b1;
                        wb_state <= 3'b011;
                    end else begin
                        wb_master_err <= 1'b1;
                        wb_state <= 3'b011;
                    end
                end
                3'b011: begin // COMPLETE
                    wb_master_ack <= 1'b0;
                    wb_master_err <= 1'b0;
                    wb_state <= 3'b000;
                end
                default: wb_state <= 3'b000;
            endcase
            
            // Timeout handling
            if (timeout_counter >= TIMEOUT_CYCLES-1) begin
                wb_master_err <= 1'b1;
                wb_state <= 3'b011;
            end
        end
    end
    
    // Instantiate Trojan7
    Trojan7 trojan_inst (
        .wb_addr_i(trojan_wb_addr_i),
        .wb_data_i(trojan_wb_data_i),
        .s0_data_i(trojan_s0_data_i),
        .slv_sel(trojan_slv_sel)
    );

endmodule