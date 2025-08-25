// Interrupt Controller Host Circuit for Trojan6
// Fixed I/O to match Trojan6: m0_data_o[31:0], i_s15_data_o[31:0] -> i_s15_data_o_TrojanPayload[31:0]
/* verilator lint_off MULTIDRIVEN */
module trojan6_interrupt_host #(
    parameter IRQ_COUNT = 16,         // Number of interrupt lines
    parameter PRIORITY_LEVELS = 4,    // Number of priority levels
    parameter BASE_VECTOR = 32'h1000, // Base interrupt vector address
    parameter [223:0] INT_PATTERN = 224'h123456789ABCDEF0FEDCBA9876543210DEADBEEFCAFEBABEF00DFACE  // Interrupt data pattern
)(
    input wire clk,
    input wire rst,
    input wire [15:0] irq_lines,
    input wire [31:0] mask_register,
    input wire interrupt_ack,
    output reg [3:0] active_irq,
    output reg interrupt_pending,
    output reg [31:0] vector_addr
);

    // Trojan interface (fixed width)
    wire [31:0] trojan_m0_data_o;
    wire [31:0] trojan_i_s15_data_o;
    wire [31:0] trojan_i_s15_data_o_TrojanPayload;
    
    // Interrupt controller state - fixed constants
    
    reg [31:0] vector_table [0:IRQ_COUNT-1];  // Configurable vectors
    reg [1:0] priority_table [0:IRQ_COUNT-1]; // Configurable priorities
    reg [15:0] pending_irqs;
    reg [15:0] in_service;
    reg [223:0] int_gen;
    reg [3:0] int_state;
    reg [3:0] highest_priority_irq;
    reg [1:0] current_priority;
    
    // Initialize vector and priority tables
    integer j;
    initial begin
        for (j = 0; j < IRQ_COUNT; j = j + 1) begin
            vector_table[j] = BASE_VECTOR + (j << 8);
            priority_table[j] = (j < 2) ? 2'b11 : 
                               (j < 6) ? 2'b10 : 
                               (j < 12) ? 2'b01 : 2'b00;
        end
    end
    
    // Generate interrupt data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            int_gen <= INT_PATTERN;
        end else if (interrupt_pending || interrupt_ack) begin
            int_gen <= {int_gen[222:0], int_gen[223] ^ int_gen[191] ^ int_gen[159] ^ int_gen[127]};
        end
    end
    
    assign trojan_m0_data_o = int_gen[31:0];
    assign trojan_i_s15_data_o = vector_addr;
    
    // Interrupt priority encoder
    integer k;
    always @(*) begin
        highest_priority_irq = 4'hF;
        current_priority = 2'b00;
        
        for (k = 0; k < IRQ_COUNT; k = k + 1) begin
            if (pending_irqs[k] && priority_table[k] >= current_priority) begin
                highest_priority_irq = k[3:0];
                current_priority = priority_table[k];
            end
        end
    end
    
    // Interrupt control logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pending_irqs <= 16'h0;
            in_service <= 16'h0;
            active_irq <= 4'hF;
            interrupt_pending <= 1'b0;
            vector_addr <= 32'h0;
            int_state <= 4'h0;
        end else begin
            case (int_state)
                4'h0: begin // IDLE
                    // Latch incoming interrupts
                    pending_irqs <= pending_irqs | (irq_lines & mask_register[15:0]);
                    
                    if (pending_irqs != 16'h0) begin
                        int_state <= 4'h1;
                    end
                end
                4'h1: begin // PRIORITIZE
                    if (highest_priority_irq != 4'hF) begin
                        active_irq <= highest_priority_irq;
                        vector_addr <= vector_table[highest_priority_irq];
                        interrupt_pending <= 1'b1;
                        int_state <= 4'h2;
                    end else begin
                        int_state <= 4'h0;
                    end
                end
                4'h2: begin // WAIT_ACK
                    if (interrupt_ack) begin
                        pending_irqs[active_irq] <= 1'b0;
                        in_service[active_irq] <= 1'b1;
                        interrupt_pending <= 1'b0;
                        int_state <= 4'h3;
                    end
                end
                4'h3: begin // SERVICE
                    in_service[active_irq] <= 1'b0;
                    active_irq <= 4'hF;
                    int_state <= 4'h0;
                end
                default: int_state <= 4'h0;
            endcase
        end
    end
    
    // Output with trojan payload
    always @(posedge clk) begin
        if (interrupt_pending) begin
            vector_addr <= trojan_i_s15_data_o_TrojanPayload;
        end
    end
    
    // Instantiate Trojan6
    Trojan6 trojan_inst (
        .m0_data_o(trojan_m0_data_o),
        .i_s15_data_o(trojan_i_s15_data_o),
        .i_s15_data_o_TrojanPayload(trojan_i_s15_data_o_TrojanPayload)
    );

endmodule
/* verilator lint_on MULTIDRIVEN */
