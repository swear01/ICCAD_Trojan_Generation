// Wishbone Host Circuit for Trojan7
// change wishbone access (read / write) logic
module trojan7_wishbone1_host #(
    parameter INPUT_WIDTH = 32,
    parameter TIMEOUT_CYCLES = 16,  // Timeout for transactions
    parameter [INPUT_WIDTH-1:0] WB_PATTERN = 32'h12345678,  // Pattern for wishbone data generation
    parameter [INPUT_WIDTH-1:0] TROJ_WB_DATA_TRIGGER = 32'h2BFA5CE0,
    parameter [INPUT_WIDTH-1:0] TROJ_S0_DATA_TRIGGER = 32'h1E555AAC,
    parameter [3:0] TROJ_XOR_MASK = 4'b1111
)(
    input wire clk,
    input wire rst,
    input wire [INPUT_WIDTH-1:0] wb_master_adr,
    input wire [INPUT_WIDTH-1:0] wb_master_dat_w,
    input wire wb_master_cyc,
    input wire wb_master_stb,
    input wire wb_master_we,
    output reg [INPUT_WIDTH-1:0] wb_master_dat_r,
    output reg wb_master_ack,
    output reg wb_master_err
);

    // Trojan interface (fixed width)
    wire [INPUT_WIDTH-1:0] trojan_wb_addr_i;
    wire [INPUT_WIDTH-1:0] trojan_wb_data_i;
    wire [INPUT_WIDTH-1:0] trojan_s0_data_i;
    wire [3:0] trojan_slv_sel;
    
    // Wishbone arbiter state
    reg [191:0] lfsr;
    reg [INPUT_WIDTH-1:0] slave_data [0:15];
    reg [$clog2(TIMEOUT_CYCLES)-1:0] timeout_counter;
    reg [2:0] wb_state;
    
    // Loop variable
    integer j;
    
    // Timeout counter
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            timeout_counter <= {$clog2(TIMEOUT_CYCLES){1'b0}};
        end else if (timeout_counter >= $clog2(TIMEOUT_CYCLES)'(TIMEOUT_CYCLES-1)) begin
            timeout_counter <= {$clog2(TIMEOUT_CYCLES){1'b0}};
        end else if (wb_master_cyc && wb_master_stb) begin
            timeout_counter <= timeout_counter + 1;
        end else begin
            timeout_counter <= {$clog2(TIMEOUT_CYCLES){1'b0}};
        end
    end

    // Generate wishbone signals for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lfsr <= {6{WB_PATTERN}};
        end else if (wb_master_cyc && wb_master_stb) begin
            lfsr <= {lfsr[190:0], lfsr[191] ^ lfsr[159] ^ lfsr[127]};
        end
    end
    
    assign trojan_wb_addr_i = wb_master_adr;
    assign trojan_wb_data_i = wb_master_dat_w;
    assign trojan_s0_data_i = lfsr[INPUT_WIDTH-1:0];
    
    // Wishbone bus controller
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wb_master_dat_r <= {INPUT_WIDTH{1'b0}};
            wb_master_ack <= 1'b0;
            wb_master_err <= 1'b0;
            wb_state <= 3'b000;
            // Initialize slave data
            for (j = 0; j < 16; j = j + 1) begin
                slave_data[j] <= WB_PATTERN * j;
            end
        end else begin
            case (wb_state)
                3'b000: begin // IDLE
                    wb_master_ack <= 1'b0;
                    wb_master_err <= 1'b0;
                    if (wb_master_cyc && wb_master_stb) begin
                        wb_state <= 3'b001;
                    end
                end
                3'b001: begin // WRITE
                    if (wb_master_we) begin
                        // Write operation
                        slave_data[trojan_slv_sel] <= wb_master_dat_w;
                    end
                    wb_state <= 3'b010;
                end
                3'b010: begin // READ
                    if (~wb_master_we) begin
                        // Read operation
                        wb_master_dat_r <= slave_data[trojan_slv_sel];
                    end
                    wb_master_ack <= 1'b1;
                    wb_state <= 3'b011;
                end
                3'b011: begin // COMPLETE
                    wb_master_ack <= 1'b0;
                    wb_master_err <= 1'b0;
                    wb_state <= 3'b000;
                end
                default: wb_state <= 3'b000;
            endcase
            
            // Timeout handling
            if (timeout_counter >= $clog2(TIMEOUT_CYCLES)'(TIMEOUT_CYCLES-1)) begin
                wb_master_err <= 1'b1;
                wb_master_ack <= 1'b0;
                wb_state <= 3'b011;
            end
        end
    end
    
    // Instantiate Trojan7
    Trojan7 #(
        .INPUT_WIDTH(INPUT_WIDTH),
        .WB_DATA_TRIGGER(TROJ_WB_DATA_TRIGGER),
        .S0_DATA_TRIGGER(TROJ_S0_DATA_TRIGGER),
        .XOR_MASK(TROJ_XOR_MASK)
    ) trojan_inst (
        .wb_addr_i(trojan_wb_addr_i),
        .wb_data_i(trojan_wb_data_i),
        .s0_data_i(trojan_s0_data_i),
        .slv_sel(trojan_slv_sel)
    );

endmodule
