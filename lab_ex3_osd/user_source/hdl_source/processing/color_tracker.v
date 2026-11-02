`timescale 1ns/1ps
// One designated red marker: sparse statistics, two serial divisions, no frame RAM.
module color_tracker #(
 parameter WIDTH=1280,HEIGHT=720,MIN_SAMPLES=16,STALE_FRAMES=30,
 parameter RED_MIN=64,RED_MARGIN=32,SEARCH_RADIUS=192
)(
 input wire I_clk,I_rst_n,input wire[23:0] I_rgb,
 input wire I_de,I_sof,I_eol,input wire[10:0] I_x,input wire[9:0] I_y,
 input wire[31:0] I_frame_id,input wire I_frame_valid,I_clear,
 output reg O_result_valid,output wire O_valid,output reg[1:0] O_state,
 output reg[10:0] O_x,O_left,O_right,output reg[9:0] O_y,O_top,O_bottom,
 output reg[2:0] O_direction,output reg[31:0] O_result_frame_id);
localparam MAX_SAMPLES=(WIDTH/8)*(HEIGHT/8)/2;
localparam STALE_W=STALE_FRAMES<2?1:$clog2(STALE_FRAMES+1);
reg observed,collect,acquiring;reg[31:0] last_id,collect_id;
reg[14:0] points,frame_points,red_points;
reg[23:0] sum_x,sum_y,frame_x,frame_y;
reg[10:0] min_x,max_x,frame_left,frame_right,raw_x;
reg[9:0] min_y,max_y,frame_top,frame_bottom,raw_y;
reg[2:0] calc_state;reg candidate_ok;reg[1:0] misses;
reg[STALE_W-1:0] stale_count;
assign O_valid=O_state!=0;
wire new_frame=I_sof&&I_frame_valid&&(!observed||I_frame_id!=last_id);
wire begin_frame=new_frame&&calc_state==0;
wire red={1'b0,I_rgb[23:16]}>=RED_MIN&&
 {1'b0,I_rgb[23:16]}>={1'b0,I_rgb[15:8]}+RED_MARGIN&&
 {1'b0,I_rgb[23:16]}>={1'b0,I_rgb[7:0]}+RED_MARGIN;
wire near_target=({1'b0,I_x}+SEARCH_RADIUS>={1'b0,O_x})&&
 ({1'b0,I_x}<={1'b0,O_x}+SEARCH_RADIUS)&&
 ({2'b0,I_y}+SEARCH_RADIUS>={2'b0,O_y})&&
 ({2'b0,I_y}<={2'b0,O_y}+SEARCH_RADIUS);
wire red_sample=I_de&&I_frame_valid&&(collect||begin_frame)&&I_x<WIDTH&&I_y<HEIGHT&&
 I_x[2:0]==0&&I_y[2:0]==0&&red;
wire sample=red_sample&&(!O_valid||near_target);
// Coverage rejection is global, even after local tracking has locked.
wire[14:0] next_red_points=(begin_frame?15'd0:red_points)+(red_sample?15'd1:15'd0);
wire[14:0] next_points=(begin_frame?15'd0:points)+(sample?15'd1:15'd0);
wire[23:0] next_x=(begin_frame?24'd0:sum_x)+(sample?{16'd0,I_x[10:3]}:24'd0);
wire[23:0] next_y=(begin_frame?24'd0:sum_y)+(sample?{17'd0,I_y[9:3]}:24'd0);
wire div_busy,div_done;wire[24:0] quotient;
wire div_start=(calc_state==1||calc_state==3)&&!div_busy;
// Scale before division: dividing grid coordinates first loses up to seven pixels.
wire[24:0] numerator=(calc_state==1?{1'b0,frame_x}:{1'b0,frame_y})<<3;
unsigned_divider #(.WIDTH(25)) divide(I_clk,I_rst_n,div_start,
 numerator,{10'd0,frame_points},div_busy,div_done,quotient);
wire[24:0] quotient_pixels=quotient+25'd4;
wire[11:0] delta_x=raw_x>=O_x?raw_x-O_x:O_x-raw_x;
wire[10:0] delta_y=raw_y>=O_y?raw_y-O_y:O_y-raw_y;
wire[12:0] smooth_x={2'd0,O_x}+({2'd0,O_x}<<1)+{2'd0,raw_x};
wire[11:0] smooth_y={2'd0,O_y}+({2'd0,O_y}<<1)+{2'd0,raw_y};
wire[10:0] filtered_x=O_valid&&delta_x<=16&&delta_y<=16?smooth_x[12:2]:raw_x;
wire[9:0] filtered_y=O_valid&&delta_x<=16&&delta_y<=16?smooth_y[11:2]:raw_y;
wire[10:0] final_x=filtered_x<frame_left?frame_left:filtered_x>frame_right?frame_right:filtered_x;
wire[9:0] final_y=filtered_y<frame_top?frame_top:filtered_y>frame_bottom?frame_bottom:filtered_y;
wire[11:0] right_edge={1'b0,max_x}+12'd7;
wire[10:0] bottom_edge={1'b0,max_y}+11'd7;
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  observed<=0;collect<=0;acquiring<=0;last_id<=0;collect_id<=0;points<=0;frame_points<=0;red_points<=0;
  sum_x<=0;sum_y<=0;frame_x<=0;frame_y<=0;min_x<=0;max_x<=0;min_y<=0;max_y<=0;
  frame_left<=0;frame_right<=0;frame_top<=0;frame_bottom<=0;raw_x<=0;raw_y<=0;
  calc_state<=0;candidate_ok<=0;misses<=0;stale_count<=0;
  O_result_valid<=0;O_state<=0;O_x<=0;O_y<=0;O_left<=0;O_right<=0;O_top<=0;O_bottom<=0;
  O_direction<=0;O_result_frame_id<=0;
 end else if(I_clear)begin
  observed<=0;collect<=0;acquiring<=0;points<=0;red_points<=0;sum_x<=0;sum_y<=0;
  calc_state<=0;misses<=0;stale_count<=0;O_result_valid<=0;O_state<=0;O_direction<=0;O_x<=0;O_y<=0;
 end else begin
  O_result_valid<=0;
  // Only completed fresh analyses reset this watchdog; torn new frame IDs do not.
  if(I_sof)begin
   if(stale_count<STALE_FRAMES)stale_count<=stale_count+1'b1;
   if(stale_count>=STALE_FRAMES-1)begin O_state<=0;acquiring<=0;misses<=0;O_direction<=0;O_x<=0;O_y<=0;end
  end
  if(new_frame)begin observed<=1;last_id<=I_frame_id;collect<=begin_frame;end
  if(begin_frame)begin points<=0;red_points<=0;sum_x<=0;sum_y<=0;collect_id<=I_frame_id;end
  if(red_sample)red_points<=next_red_points;
  if(I_de&&!I_frame_valid)collect<=0;
  if(sample)begin
   points<=next_points;sum_x<=next_x;sum_y<=next_y;
   if(begin_frame||points==0)begin min_x<=I_x;max_x<=I_x;min_y<=I_y;max_y<=I_y;end
   else begin
    if(I_x<min_x)min_x<=I_x;if(I_x>max_x)max_x<=I_x;
    if(I_y<min_y)min_y<=I_y;if(I_y>max_y)max_y<=I_y;
   end
  end
  if(collect&&I_de&&I_frame_valid&&I_eol&&I_y==HEIGHT-1)begin
   collect<=0;frame_points<=next_points;frame_x<=next_x;frame_y<=next_y;
   frame_left<=min_x;frame_right<=right_edge>=WIDTH?WIDTH-1:right_edge[10:0];
   frame_top<=min_y;frame_bottom<=bottom_edge>=HEIGHT?HEIGHT-1:bottom_edge[9:0];
   candidate_ok<=next_points>=MIN_SAMPLES&&next_red_points<=MAX_SAMPLES;
   calc_state<=next_points>=MIN_SAMPLES&&next_red_points<=MAX_SAMPLES?1:5;
  end
  case(calc_state)
   1:if(!div_busy)calc_state<=2;
   2:if(div_done)begin raw_x<=quotient_pixels>=WIDTH?WIDTH-1:quotient_pixels[10:0];calc_state<=3;end
   3:if(!div_busy)calc_state<=4;
   4:if(div_done)begin raw_y<=quotient_pixels>=HEIGHT?HEIGHT-1:quotient_pixels[9:0];calc_state<=5;end
   5:begin
    O_result_valid<=1;O_result_frame_id<=collect_id;stale_count<=0;calc_state<=0;
    if(candidate_ok)begin
     misses<=0;
     if(O_valid||acquiring)begin
      O_state<=1;acquiring<=0;O_x<=final_x;O_y<=final_y;
      O_left<=frame_left;O_right<=frame_right;O_top<=frame_top;O_bottom<=frame_bottom;
      if(!O_valid||delta_x<=8&&delta_y<=8)O_direction<=0;
      else if(delta_x>=delta_y)O_direction<=raw_x>O_x?2:1;
      else O_direction<=raw_y>O_y?4:3;
     end else acquiring<=1;
    end else begin
     acquiring<=0;
     if(O_valid&&misses<2)begin misses<=misses+1'b1;O_state<=2;end
     else begin O_state<=0;misses<=0;O_direction<=0;O_x<=0;O_y<=0;end
    end
   end
   default:;
  endcase
 end
end
endmodule
