// Exception Handler Host Circuit for Trojan5
// Fixed I/O to match Trojan5: pon_rst_n_i, prog_dat_i[13:0], pc_reg[12:0] -> prog_adr_o[12:0]
module trojan5_exception_host #(
    parameter VECTOR_TABLE_SIZE = 16,  // Exception vector table size
    parameter STACK_SIZE = 64          // Exception stack size
)(
    input wire clk,
    input wire pon_rst_n_i,
    input wire [3:0] exception_code,
    input wire exception_request,
    input wire [12:0] exception_pc,
    input wire [15:0] exception_data,
    input wire return_from_exception,
    output reg [12:0] exception_vector,
    output reg exception_active,
    output reg exception_ack,
    output reg [15:0] saved_data
);

    // Trojan interface (fixed width)
    wire [13:0] trojan_prog_dat_i;
    wire [12:0] trojan_pc_reg;
    wire [12:0] trojan_prog_adr_o;
    
    // Exception handling state
    reg [12:0] vector_table [0:VECTOR_TABLE_SIZE-1];
    reg [12:0] exception_stack [0:STACK_SIZE-1];
    reg [15:0] data_stack [0:STACK_SIZE-1];
    reg [5:0] stack_pointer;
    
    reg [31:0] exception_pattern;
    reg [12:0] handler_pc;
    reg [3:0] exception_state;
    reg [3:0] current_exception;
    reg [7:0] exception_counter;
    
    // Initialize exception vector table
    initial begin
        vector_table[0]  = 13'h0100;  // Reset
        vector_table[1]  = 13'h0110;  // Illegal instruction
        vector_table[2]  = 13'h0120;  // Division by zero
        vector_table[3]  = 13'h0130;  // Overflow
        vector_table[4]  = 13'h0140;  // Underflow
        vector_table[5]  = 13'h0150;  // Memory fault
        vector_table[6]  = 13'h0160;  // Bus error
        vector_table[7]  = 13'h0170;  // Interrupt 0
        vector_table[8]  = 13'h0180;  // Interrupt 1
        vector_table[9]  = 13'h0190;  // Interrupt 2
        vector_table[10] = 13'h01A0;  // Interrupt 3
        vector_table[11] = 13'h01B0;  // Interrupt 4
        vector_table[12] = 13'h01C0;  // Interrupt 5
        vector_table[13] = 13'h01D0;  // Interrupt 6
        vector_table[14] = 13'h01E0;  // Interrupt 7
        vector_table[15] = 13'h01F0;  // Reserved
    end
    
    // Generate program data from exception handling
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            exception_pattern <= 32'hE0009000;
            handler_pc <= 13'h0;
            exception_counter <= 8'h0;
        end else if (exception_request || return_from_exception) begin
            exception_pattern <= {exception_pattern[30:0], exception_pattern[31] ^ exception_pattern[26] ^ exception_pattern[20] ^ exception_pattern[12]};
            handler_pc <= vector_table[{{(32-4){1'b0}}, exception_code} % VECTOR_TABLE_SIZE];
            exception_counter <= exception_counter + 1;
        end
    end
    
    assign trojan_prog_dat_i = exception_pattern[13:0] ^ {10'b0, exception_code};
    assign trojan_pc_reg = handler_pc;
    
    // Exception handling state machine
    integer i;
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            for (i = 0; i < STACK_SIZE; i = i + 1) begin
                exception_stack[i] <= 13'h0;
                data_stack[i] <= 16'h0;
            end
            stack_pointer <= 6'h0;
            exception_vector <= 13'h0;
            exception_active <= 1'b0;
            exception_ack <= 1'b0;
            saved_data <= 16'h0;
            exception_state <= 4'h0;
            current_exception <= 4'h0;
        end else begin
            case (exception_state)
                4'h0: begin // IDLE
                    exception_ack <= 1'b0;
                    if (exception_request) begin
                        current_exception <= exception_code;
                        exception_state <= 4'h1;
                    end else if (return_from_exception && stack_pointer > 0) begin
                        exception_state <= 4'h4;
                    end
                end
                4'h1: begin // SAVE_CONTEXT
                    // Push current PC and data to stack
                    exception_stack[stack_pointer] <= exception_pc;
                    data_stack[stack_pointer] <= exception_data;
                    /* verilator lint_off WIDTHTRUNC */
                    stack_pointer <= (stack_pointer + 1) % STACK_SIZE;
                    /* verilator lint_on WIDTHTRUNC */
                    exception_state <= 4'h2;
                end
                4'h2: begin // LOAD_VECTOR
                    exception_vector <= vector_table[{{(32-4){1'b0}}, current_exception} % VECTOR_TABLE_SIZE];
                    exception_active <= 1'b1;
                    exception_state <= 4'h3;
                end
                4'h3: begin // ACK
                    exception_ack <= 1'b1;
                    exception_state <= 4'h0;
                end
                4'h4: begin // RESTORE_CONTEXT
                    // Pop from stack
                    stack_pointer <= stack_pointer - 1;
                    exception_vector <= exception_stack[stack_pointer - 1];
                    saved_data <= data_stack[stack_pointer - 1];
                    exception_state <= 4'h5;
                end
                4'h5: begin // RETURN
                    exception_active <= 1'b0;
                    exception_ack <= 1'b1;
                    exception_state <= 4'h0;
                end
                default: exception_state <= 4'h0;
            endcase
        end
    end
    
    // Exception vector modification using trojan output
    always @(posedge clk) begin
        if (exception_active && (exception_counter[2:0] == 3'b100)) begin
            // Modify exception vector based on trojan address output
            exception_vector <= exception_vector ^ trojan_prog_adr_o;
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
