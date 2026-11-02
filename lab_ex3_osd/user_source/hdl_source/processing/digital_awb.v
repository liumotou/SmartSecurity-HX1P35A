`timescale 1ns/1ps
module digital_awb #(parameter WIDTH=1280,HEIGHT=720,MIN_SAMPLES=256)(
 input wire I_clk,I_rst_n,input wire[23:0] I_rgb,input wire I_de,I_hs,I_vs,I_sof,I_eol,
 input wire[10:0] I_x,input wire[9:0] I_y,input wire[31:0] I_frame_id,input wire I_frame_valid,I_enable,
 output wire[23:0] O_rgb,output wire O_de,O_hs,O_vs,O_sof,O_eol,
 output wire[10:0] O_x,output wire[9:0] O_y,output wire[31:0] O_frame_id,output wire O_frame_valid,
 output reg[9:0] O_gain_r,O_gain_g,O_gain_b);
reg[82:0] packet0,packet1;reg[17:0] red_product,green_product,blue_product;reg enabled_d;
reg observed,collect,pending;reg[31:0] last_id;reg[23:0] sr,sg,sb,lr,lg,lb;
reg[14:0] samples;reg[3:0] state;reg[47:0] mean_scaled;
reg[9:0] target_r,target_g,target_b;
function[9:0] clamp;input[47:0] value;begin clamp=value<128?128:value>512?512:value[9:0];end endfunction
function[9:0] step_gain;input[9:0] old_gain,target;begin
 if(target>old_gain+16)step_gain=old_gain+16;
 else if(target+16<old_gain)step_gain=old_gain-16;else step_gain=target;
end endfunction
wire new_frame=I_sof&&I_frame_valid&&(!observed||I_frame_id!=last_id);
wire[9:0] effective_r=new_frame&&pending&&I_enable?step_gain(O_gain_r,target_r):O_gain_r;
wire[9:0] effective_g=new_frame&&pending&&I_enable?step_gain(O_gain_g,target_g):O_gain_g;
wire[9:0] effective_b=new_frame&&pending&&I_enable?step_gain(O_gain_b,target_b):O_gain_b;
wire qualify=I_rgb[23:16]>8&&I_rgb[23:16]<248&&I_rgb[15:8]>8&&I_rgb[15:8]<248&&I_rgb[7:0]>8&&I_rgb[7:0]<248;
wire sample=I_de&&I_frame_valid&&(collect||new_frame)&&I_x[2:0]==0&&I_y[2:0]==0&&qualify;
wire div_start=state==1||state==3||state==5||state==7;
wire[47:0] numerator=state==1?({24'd0,lr}+{24'd0,lg}+{24'd0,lb}):mean_scaled;
wire[47:0] denominator=state==1?48'd3:state==3?{24'd0,lr}:state==5?{24'd0,lg}:{24'd0,lb};
wire busy,done;wire[47:0] quotient;
unsigned_divider divide(I_clk,I_rst_n,div_start,numerator,denominator,busy,done,quotient);
assign {O_frame_valid,O_frame_id,O_x,O_y,O_de,O_hs,O_vs,O_sof,O_eol,O_rgb}=packet1;
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin packet0<=0;packet1<=0;red_product<=0;green_product<=0;blue_product<=0;enabled_d<=0;
  O_gain_r<=256;O_gain_g<=256;O_gain_b<=256;target_r<=256;target_g<=256;target_b<=256;
  observed<=0;collect<=0;pending<=0;last_id<=0;sr<=0;sg<=0;sb<=0;lr<=0;lg<=0;lb<=0;samples<=0;state<=0;mean_scaled<=0;
 end else begin
  packet0<={I_frame_valid,I_frame_id,I_x,I_y,I_de,I_hs,I_vs,I_sof,I_eol,I_rgb};packet1<=packet0;enabled_d<=I_enable;
  red_product<=I_rgb[23:16]*effective_r;green_product<=I_rgb[15:8]*effective_g;blue_product<=I_rgb[7:0]*effective_b;
  if(enabled_d)begin
   packet1[23:16]<=red_product[17:8]>255?8'd255:red_product[15:8];
   packet1[15:8]<=green_product[17:8]>255?8'd255:green_product[15:8];
   packet1[7:0]<=blue_product[17:8]>255?8'd255:blue_product[15:8];
  end
  if(new_frame)begin
   observed<=1;last_id<=I_frame_id;collect<=1;sr<=0;sg<=0;sb<=0;samples<=0;
   if(pending&&I_enable)begin O_gain_r<=effective_r;O_gain_g<=effective_g;O_gain_b<=effective_b;pending<=0;end
  end
  if(I_de&&!I_frame_valid)collect<=0;
  if(sample)begin
   sr<=(new_frame?24'd0:sr)+I_rgb[23:16];sg<=(new_frame?24'd0:sg)+I_rgb[15:8];sb<=(new_frame?24'd0:sb)+I_rgb[7:0];
   samples<=(new_frame?15'd0:samples)+1'b1;
  end
  if(collect&&I_frame_valid&&I_de&&I_eol&&I_y==HEIGHT-1)begin
   collect<=0;
   if(samples>=MIN_SAMPLES&&sr!=0&&sg!=0&&sb!=0&&state==0)begin lr<=sr;lg<=sg;lb<=sb;state<=1;end
  end
  case(state)
   1,3,5,7:state<=state+1'b1;
   2:if(done)begin mean_scaled<=quotient<<8;state<=3;end
   4:if(done)begin target_r<=clamp(quotient);state<=5;end
   6:if(done)begin target_g<=clamp(quotient);state<=7;end
   8:if(done)begin target_b<=clamp(quotient);pending<=1;state<=0;end
   default:;
  endcase
 end
end
endmodule
