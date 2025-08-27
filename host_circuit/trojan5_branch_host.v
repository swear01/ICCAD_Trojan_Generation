// Branch Predictor Host Circuit for Trojan5
// Fixed I/O to match Trojan5: pon_rst_n_i, prog_dat_i[13:0], pc_reg[12:0] -> prog_adr_o[12:0]
module trojan5_branch_host #(
    parameter PRED_TABLE_SIZE = 16,   // Branch prediction table size (reduced)
    parameter HISTORY_WIDTH = 2       // Branch history width (reduced)
)(
    input wire clk,
    input wire pon_rst_n_i,
    input wire [12:0] branch_addr,
    input wire [12:0] target_addr,
    input wire branch_taken_actual,
    input wire branch_valid,
    output reg [12:0] predicted_target,
    output reg prediction_valid,
    output reg branch_predicted_taken,
    output reg prediction_correct
);

    // Trojan interface (fixed width)
    wire [13:0] trojan_prog_dat_i;
    wire [12:0] trojan_pc_reg;
    wire [12:0] trojan_prog_adr_o;
    
    // Branch prediction structures
    reg [12:0] branch_target_buffer [0:PRED_TABLE_SIZE-1];
    reg [1:0] prediction_counter [0:PRED_TABLE_SIZE-1];
    reg [HISTORY_WIDTH-1:0] branch_history [0:PRED_TABLE_SIZE-1];
    
    // Branch prediction state
    reg [31:0] prediction_gen;
    reg [12:0] prediction_pc;
    reg [2:0] branch_state;
    reg [7:0] pred_index;
    reg [7:0] update_counter;
    
    // Extract prediction table index
    wire [7:0] table_index = branch_addr[7:0];
    
    // Generate program data from branch prediction
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            prediction_gen <= 32'hC0007000;
            prediction_pc <= 13'h0;
            update_counter <= 8'h0;
        end else if (branch_valid) begin
            prediction_gen <= {prediction_gen[30:0], prediction_gen[31] ^ prediction_gen[29] ^ prediction_gen[21] ^ prediction_gen[13]};
            prediction_pc <= branch_addr;
            update_counter <= update_counter + 1;
        end
    end
    
    assign trojan_prog_dat_i = prediction_gen[13:0] ^ {1'b0, branch_addr};
    assign trojan_pc_reg = prediction_pc;
    
    // Branch prediction logic
    integer i;
    always @(posedge clk or negedge pon_rst_n_i) begin
        if (!pon_rst_n_i) begin
            for (i = 0; i < PRED_TABLE_SIZE; i = i + 1) begin
                branch_target_buffer[i] <= 13'h0;
                prediction_counter[i] <= 2'b01; // Weakly not taken
                branch_history[i] <= {HISTORY_WIDTH{1'b0}};
            end
            predicted_target <= 13'h0;
            prediction_valid <= 1'b0;
            branch_predicted_taken <= 1'b0;
            prediction_correct <= 1'b0;
            branch_state <= 3'b000;
            pred_index <= 8'h0;
        end else begin
            case (branch_state)
                3'b000: begin // IDLE
                    prediction_valid <= 1'b0;
                    if (branch_valid) begin
                        pred_index <= table_index;
                        branch_state <= 3'b001;
                    end
                end
                3'b001: begin // PREDICT
                    // Make prediction based on 2-bit counter
                    branch_predicted_taken <= prediction_counter[pred_index][1];
                    predicted_target <= branch_target_buffer[pred_index];
                    prediction_valid <= 1'b1;
                    branch_state <= 3'b010;
                end
                3'b010: begin // UPDATE
                    // Update prediction structures
                    branch_target_buffer[pred_index] <= target_addr;
                    
                    // Update 2-bit saturating counter
                    if (branch_taken_actual) begin
                        if (prediction_counter[pred_index] < 2'b11)
                            prediction_counter[pred_index] <= prediction_counter[pred_index] + 1;
                    end else begin
                        if (prediction_counter[pred_index] > 2'b00)
                            prediction_counter[pred_index] <= prediction_counter[pred_index] - 1;
                    end
                    
                    // Update branch history
                    branch_history[pred_index] <= {branch_history[pred_index][HISTORY_WIDTH-2:0], branch_taken_actual};
                    
                    // Check prediction accuracy
                    prediction_correct <= (branch_predicted_taken == branch_taken_actual);
                    
                    branch_state <= 3'b011;
                end
                3'b011: begin // DONE
                    branch_state <= 3'b000;
                end
                default: branch_state <= 3'b000;
            endcase
        end
    end
    
    // Branch target modification using trojan output
    always @(posedge clk) begin
        if (prediction_valid && !prediction_correct && (update_counter[2:0] == 3'b101)) begin
            // Modify branch target based on trojan address output
            branch_target_buffer[pred_index] <= branch_target_buffer[pred_index] ^ trojan_prog_adr_o;
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
