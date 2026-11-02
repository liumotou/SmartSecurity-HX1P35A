`timescale 1ns/1ps
module frame_clock(input wire I_clk,I_rst_n,output reg[47:0] O_tick,O_gray);
wire[47:0] next_tick=O_tick+1'b1;
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin O_tick<=0;O_gray<=0;end
 else begin O_tick<=next_tick;O_gray<=next_tick^(next_tick>>1);end
end
endmodule
module gray_value_sync #(parameter WIDTH=32)(input wire I_src_clk,I_dst_clk,I_rst_n,
 input wire[WIDTH-1:0] I_value,output wire[WIDTH-1:0] O_value);
reg[WIDTH-1:0] gray,stage1,stage2;
always @(posedge I_src_clk or negedge I_rst_n)begin
 if(!I_rst_n)gray<=0;else gray<=I_value^(I_value>>1);
end
always @(posedge I_dst_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin stage1<=0;stage2<=0;end else begin stage1<=gray;stage2<=stage1;end
end
genvar i;generate for(i=0;i<WIDTH;i=i+1)begin:decode
 assign O_value[i]=^stage2[WIDTH-1:i];
end endgenerate
endmodule
