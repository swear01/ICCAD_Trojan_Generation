// Vector Host Circuit for Trojan8
// Fixed I/O to match Trojan8: a,b,c,d,e[7:0], sel[2:0] -> y[15:0]
module trojan8_vector_host (
    input wire clk,
    input wire rst,
    input wire [63:0] vector_a_flat,   // Fixed: 8x8 = 64 bits
    input wire [63:0] vector_b_flat,   // Fixed: 8x8 = 64 bits  
    input wire [2:0] vector_op,
    input wire compute_enable,
    output reg [127:0] vector_result_flat, // Fixed: 8x16 = 128 bits
    output reg compute_done
);

    // Trojan interface (fixed width)
    wire [7:0] trojan_a, trojan_b, trojan_c, trojan_d, trojan_e;
    wire [2:0] trojan_sel;
    wire [15:0] trojan_y;
    
    // Vector processing state
    reg [63:0] vec_gen;
    reg [2:0] process_index;
    reg [2:0] vec_state;
    
    // Helper function for vector element indexing
    function integer get_vector_index;
        input [2:0] idx;
        begin
            get_vector_index = {29'b0, idx} << 3;  // idx * 8
        end
    endfunction
    
    function integer get_result_index;
        input [2:0] idx;
        begin
            get_result_index = {29'b0, idx} << 4;  // idx * 16
        end
    endfunction
    
    // Generate vector data for trojan
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vec_gen <= 64'h123456789ABCDEF0;
            process_index <= 3'b0;
        end else if (compute_enable) begin
            vec_gen <= {vec_gen[62:0], vec_gen[63] ^ vec_gen[31] ^ vec_gen[15]};
        end
    end
    
    // Extract trojan inputs from vector processing
    assign trojan_a = vector_a_flat[get_vector_index(process_index) +: 8];
    assign trojan_b = vector_b_flat[get_vector_index(process_index) +: 8];
    assign trojan_c = vec_gen[23:16];
    assign trojan_d = vec_gen[15:8];
    assign trojan_e = vec_gen[7:0];
    assign trojan_sel = vector_op;
    
    // Vector processing state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            process_index <= 3'b0;
            compute_done <= 1'b0;
            vec_state <= 3'b000;
            vector_result_flat <= 128'h0;
        end else begin
            case (vec_state)
                3'b000: begin // IDLE
                    compute_done <= 1'b0;
                    if (compute_enable) begin
                        process_index <= 3'b0;
                        vec_state <= 3'b001;
                    end
                end
                3'b001: begin // COMPUTE
                    // Process vector element with trojan output
                    if (process_index < 3'd7) begin
                        vector_result_flat[get_result_index(process_index) +: 16] <= trojan_y;
                        process_index <= process_index + 1;
                    end else begin
                        // Handle last element
                        vector_result_flat[get_result_index(process_index) +: 16] <= trojan_y;
                        vec_state <= 3'b010;
                    end
                end
                3'b010: begin // COMPLETE
                    compute_done <= 1'b1;
                    vec_state <= 3'b000;
                end
                default: vec_state <= 3'b000;
            endcase
        end
    end
    
    // Instantiate Trojan8
    Trojan8 trojan_inst (
        .a(trojan_a),
        .b(trojan_b),
        .c(trojan_c),
        .d(trojan_d),
        .e(trojan_e),
        .sel(trojan_sel),
        .y(trojan_y)
    );

endmodule
