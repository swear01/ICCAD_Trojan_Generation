module Trojan1(
	input clk,
	input rst,
	input r1,
	output trigger
    );

	reg [3: 0] counter;
	
	always @ (posedge clk or posedge rst)
		begin
			if (rst) begin
				counter <= 4'b0000;
			end
			else if (r1 == 1'b1) begin
				counter <= counter + 1'b1;
			end		
		end
	assign trigger = counter[3];

endmodule