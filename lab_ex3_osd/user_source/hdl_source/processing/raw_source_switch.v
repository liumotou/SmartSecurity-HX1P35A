`timescale 1ns/1ps
// Drain the active source's complete frame, then wait for destination SOF.
module raw_source_switch #(parameter integer HEIGHT=720)(input wire I_clk,I_rst_n,I_request,
 input wire[39:0] I_a_data,input wire I_a_valid,I_a_user,I_a_last,
 input wire[39:0] I_b_data,input wire I_b_valid,I_b_user,I_b_last,
 output reg[39:0] O_data,output reg O_valid,O_user,O_last,O_selected);
reg running;reg[9:0] line;
wire select=running?O_selected:I_request;
wire valid=select?I_b_valid:I_a_valid;
wire user=select?I_b_user:I_a_user;
wire last=select?I_b_last:I_a_last;
always @(posedge I_clk or negedge I_rst_n) begin
 if(!I_rst_n) begin running<=0;line<=0;O_selected<=0;O_data<=0;O_valid<=0;O_user<=0;O_last<=0;end
 else begin
  O_valid<=0;O_user<=0;O_last<=0;
  if(valid&&(running||user)) begin
   O_data<=select?I_b_data:I_a_data;O_valid<=1;O_user<=user;O_last<=last;
   if(!running||user) begin running<=1;line<=0;O_selected<=select;end
   if(last) begin
    if(line==HEIGHT-1) begin line<=0;if(I_request!=select) running<=0;end
    else line<=line+1'b1;
   end
  end
 end
end
endmodule
