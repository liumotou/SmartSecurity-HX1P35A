`timescale 1ns/1ps
// Payload held from request until acknowledged; destination sees an atomic word.
module cdc_mailbox #(parameter WIDTH=80)(input wire I_src_clk,I_dst_clk,I_rst_n,I_send,
 input wire[WIDTH-1:0] I_data,output wire O_busy,output reg O_valid,output reg[WIDTH-1:0] O_data);
reg request,ack;reg[1:0] ack_sync,req_sync;reg[WIDTH-1:0] held;
assign O_busy=request!=ack_sync[1];
always @(posedge I_src_clk or negedge I_rst_n) begin
 if(!I_rst_n) begin request<=0;ack_sync<=0;held<=0;end
 else begin ack_sync<={ack_sync[0],ack};if(I_send&&!O_busy) begin held<=I_data;request<=!request;end end
end
always @(posedge I_dst_clk or negedge I_rst_n) begin
 if(!I_rst_n) begin req_sync<=0;ack<=0;O_data<=0;O_valid<=0;end
 else begin req_sync<={req_sync[0],request};O_valid<=0;
  if(req_sync[1]!=ack) begin O_data<=held;O_valid<=1;ack<=req_sync[1];end
 end
end
endmodule
