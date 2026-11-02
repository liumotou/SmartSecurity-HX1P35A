`timescale 1ns/1ps
module video_controls(input wire I_clk,I_rst_n,I_sof,I_mode_next,I_level_next,I_wb_toggle,
 output reg[2:0] O_mode,output reg[1:0] O_level,output reg O_wb,
 input wire I_zone_next,output reg[1:0] O_zone);
reg[2:0] pending_mode;reg[1:0] pending_level,pending_zone;reg pending_wb;
always @(posedge I_clk or negedge I_rst_n) begin
 if(!I_rst_n) begin pending_mode<=0;pending_level<=1;pending_wb<=0;pending_zone<=1;O_mode<=0;O_level<=1;O_wb<=0;O_zone<=1;end
 else begin
  if(I_mode_next) pending_mode<=pending_mode==6?0:pending_mode+1'b1;
  if(I_zone_next)pending_zone<=pending_zone+1'b1;
  if(I_level_next) pending_level<=pending_level==2?0:pending_level+1'b1;
  if(I_wb_toggle) pending_wb<=!pending_wb;
  if(I_sof) begin O_mode<=pending_mode;O_level<=pending_level;O_wb<=pending_wb;O_zone<=pending_zone;end
 end
end
endmodule
