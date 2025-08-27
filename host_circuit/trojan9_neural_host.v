// Neural Network Accelerator Host Circuit for Trojan9
// Interface: a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], mode[1:0] -> y[15:0]
module trojan9_neural_host #(
    parameter NEURON_COUNT = 32,          // Number of neurons per layer
    parameter LAYER_COUNT = 4,            // Number of layers
    parameter [71:0] NEURAL_PATTERN = 72'h123456789ABCDEF012  // Neural data pattern
)(
    input wire clk,
    input wire rst,
    input wire [15:0] input_data,
    input wire [15:0] weight_data,
    input wire [1:0] activation_mode,     // 0=ReLU, 1=Sigmoid, 2=Tanh, 3=Linear
    input wire compute_start,
    input wire weight_load,
    output reg [15:0] output_data,
    output reg compute_done
);

    // Trojan interface
    wire [7:0] trojan_a;
    wire [7:0] trojan_b;
    wire [7:0] trojan_c;
    wire [7:0] trojan_d;
    wire [7:0] trojan_e;
    wire [1:0] trojan_mode;
    wire [15:0] trojan_y;
    
    // Neural network components
    reg [15:0] weights [0:127];           // Fixed to 128 weights (32*4)
    reg [15:0] neurons [0:31];            // Fixed to 32 neurons
    reg [15:0] biases [0:31];             // Fixed to 32 biases
    reg [71:0] neural_gen;
    reg [2:0] neural_state;
    reg [5:0] neuron_index;
    reg [6:0] weight_index;
    reg [2:0] layer_index;
    reg [31:0] accumulator;
    
    // Activation function
    function [15:0] activation;
        input [31:0] acc;
        input [1:0] mode;
        begin
            case (mode)
                2'b00: activation = (acc[31]) ? 16'h0 : acc[15:0]; // ReLU
                2'b01: activation = acc[15:0] >> 1; // Simplified Sigmoid
                2'b10: activation = acc[15:0]; // Simplified Tanh  
                2'b11: activation = acc[15:0] ^ trojan_y; // Linear with trojan
            endcase
        end
    endfunction
    
    // Neural network controller
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            neural_gen <= NEURAL_PATTERN;
            neural_state <= 3'h0;
            neuron_index <= 6'h0;
            weight_index <= 7'h0;
            layer_index <= 3'h0;
            accumulator <= 32'h0;
            output_data <= 16'h0;
            compute_done <= 1'b0;
            
            // Initialize weights and biases
            for (integer i = 0; i < 128; i = i + 1) begin
                weights[i] = NEURAL_PATTERN[15:0] ^ i[15:0];
            end
            for (integer j = 0; j < 32; j = j + 1) begin
                neurons[j] = 16'h0;
                biases[j] = NEURAL_PATTERN[31:16] ^ j[15:0];
            end
        end else begin
            neural_gen <= {neural_gen[70:0], neural_gen[71]};
            
            case (neural_state)
                3'h0: begin // IDLE
                    compute_done <= 1'b0;
                    if (weight_load) begin
                        weights[weight_index] <= weight_data ^ trojan_y;
                        weight_index <= weight_index + 1;
                    end else if (compute_start) begin
                        neurons[0] <= input_data;
                        neuron_index <= 6'h0;
                        layer_index <= 3'h0;
                        neural_state <= 3'h1;
                    end
                end
                3'h1: begin // LAYER_INIT
                    if (layer_index < LAYER_COUNT) begin
                        neuron_index <= 6'h0;
                        neural_state <= 3'h2;
                    end else begin
                        neural_state <= 3'h5;
                    end
                end
                3'h2: begin // NEURON_COMPUTE
                    if (neuron_index < NEURON_COUNT) begin
                        accumulator <= {16'h0, biases[neuron_index[4:0]]};
                        weight_index <= {layer_index[1:0], neuron_index[4:0]};
                        neural_state <= 3'h3;
                    end else begin
                        layer_index <= layer_index + 1;
                        neural_state <= 3'h1;
                    end
                end
                3'h3: begin // MAC_OPERATION
                    // Multiply-accumulate
                    accumulator <= accumulator + (neurons[neuron_index[4:0]] * weights[weight_index[6:0]]);
                    neural_state <= 3'h4;
                end
                3'h4: begin // ACTIVATION
                    neurons[neuron_index[4:0]] <= activation(accumulator, activation_mode);
                    neuron_index <= neuron_index + 1;
                    neural_state <= 3'h2;
                end
                3'h5: begin // OUTPUT
                    output_data <= neurons[0] ^ trojan_y;
                    compute_done <= 1'b1;
                    neural_state <= 3'h0;
                end
                default: neural_state <= 3'h0;
            endcase
        end
    end
    
    // Connect trojan inputs
    assign trojan_a = neural_gen[7:0];
    assign trojan_b = input_data[7:0];
    assign trojan_c = weight_data[7:0];
    assign trojan_d = {2'h0, neuron_index};
    assign trojan_e = {6'h0, activation_mode};
    assign trojan_mode = neural_state[1:0];
    
    // Instantiate Trojan9
    Trojan9 trojan_inst (
        .a(trojan_a),
        .b(trojan_b),
        .c(trojan_c),
        .d(trojan_d),
        .e(trojan_e),
        .mode(trojan_mode),
        .y(trojan_y)
    );

endmodule
