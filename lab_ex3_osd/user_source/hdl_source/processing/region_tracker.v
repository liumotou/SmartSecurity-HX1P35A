`timescale 1ns/1ps
module region_tracker(input wire I_clk,I_rst_n,I_clear,I_new_frame,input wire[31:0] I_frame_id,
 input wire I_result_valid,input wire[31:0] I_result_frame_id,input wire I_candidate_valid,I_scene_change,
 input wire[10:0] I_left,I_right,input wire[9:0] I_top,I_bottom,I_area,
 output reg O_active,output reg[2:0] O_state,output reg[10:0] O_left,O_right,
 output reg[9:0] O_top,O_bottom,output wire[10:0] O_center_x,output wire[9:0] O_center_y,
 output reg[9:0] O_area,output reg[31:0] O_result_frame_id,output reg[2:0] O_direction);
reg observed,result_seen;reg[31:0] observed_id,last_result;reg[4:0] misses;reg hit;
wire[11:0] center_x_sum={1'b0,O_left}+{1'b0,O_right};
wire[10:0] center_y_sum={1'b0,O_top}+{1'b0,O_bottom};
assign O_center_x=center_x_sum[11:1];assign O_center_y=center_y_sum[10:1];
wire[31:0] elapsed=I_frame_id-observed_id;
wire[32:0] new_misses={28'd0,misses}+{1'b0,elapsed};
wire advancing=I_new_frame&&(!observed||$signed(elapsed)>0);
wire[31:0] newest_id=advancing?I_frame_id:observed_id;
wire[31:0] result_age=observed&&$signed(newest_id-I_result_frame_id)>0?newest_id-I_result_frame_id:0;
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin O_active<=0;O_state<=0;O_left<=0;O_right<=0;O_top<=0;O_bottom<=0;
  O_area<=0;O_result_frame_id<=0;O_direction<=0;observed<=0;result_seen<=0;observed_id<=0;last_result<=0;misses<=0;hit<=0;end
 else if(I_clear)begin O_active<=0;O_state<=0;observed<=0;result_seen<=0;misses<=0;hit<=0;O_direction<=0;end
 else begin
  if(advancing)begin
   observed<=1;observed_id<=I_frame_id;
   if(O_active)begin
    if(new_misses>=15)begin O_active<=0;O_state<=3;misses<=15;hit<=0;end
    else begin misses<=new_misses[4:0];if(new_misses>=2&&O_state!=4)O_state<=2;end
   end
  end
  if(I_result_valid&&(!result_seen||I_result_frame_id!=last_result))begin
   result_seen<=1;last_result<=I_result_frame_id;
   if(I_scene_change)begin O_state<=4;hit<=0;end
   else if(I_candidate_valid)begin
    hit<=1;
    if(O_active||hit)begin
     O_active<=result_age<15;O_state<=result_age<15?1:3;misses<=result_age>=15?15:result_age[4:0];
     O_area<=I_area;O_result_frame_id<=I_result_frame_id;
     observed<=1;observed_id<=observed&&$signed(newest_id-I_result_frame_id)>0?newest_id:I_result_frame_id;
     if(O_active)begin
      O_left<=({2'b0,O_left}*3+{2'b0,I_left})>>2;
      O_right<=({2'b0,O_right}*3+{2'b0,I_right})>>2;
      O_top<=({2'b0,O_top}*3+{2'b0,I_top})>>2;
      O_bottom<=({2'b0,O_bottom}*3+{2'b0,I_bottom})>>2;
      if(({1'b0,I_left}+I_right)>({1'b0,O_left}+O_right)+8)O_direction<=2;
      else if(({1'b0,I_left}+I_right)+8<({1'b0,O_left}+O_right))O_direction<=1;
      else if(({1'b0,I_top}+I_bottom)>({1'b0,O_top}+O_bottom)+8)O_direction<=4;
      else if(({1'b0,I_top}+I_bottom)+8<({1'b0,O_top}+O_bottom))O_direction<=3;
      else O_direction<=0;
     end else begin O_left<=I_left;O_right<=I_right;O_top<=I_top;O_bottom<=I_bottom;O_direction<=0;end
    end else O_state<=0;
   end else begin hit<=0;if(O_active)O_state<=2;end
  end
 end
end
endmodule
