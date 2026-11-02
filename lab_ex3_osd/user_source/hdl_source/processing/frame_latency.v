`timescale 1ns/1ps
module frame_latency(input wire I_clk,I_rst_n,I_sof,I_frame_valid,
 input wire[47:0] I_capture_tick,I_now_tick,output reg O_valid,output reg[31:0] O_ms);
reg start,pending_valid;reg[47:0] interval;wire busy,done;wire[47:0] quotient;
unsigned_divider divide(I_clk,I_rst_n,start,interval,48'd100000,busy,done,quotient);
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin start<=0;pending_valid<=0;interval<=0;O_valid<=0;O_ms<=0;end
 else begin start<=0;
  if(I_sof)begin
   O_valid<=0;pending_valid<=I_frame_valid;
   if(I_frame_valid&&!busy)begin interval<=I_now_tick-I_capture_tick;start<=1;end
  end
  if(done&&pending_valid)begin O_ms<=quotient[31:0];O_valid<=1;end
 end
end
endmodule
