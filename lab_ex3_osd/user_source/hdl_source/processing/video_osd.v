`timescale 1ns/1ps
module video_osd(input wire I_clk,I_rst_n,input wire[23:0] I_rgb,input wire I_de,I_hs,I_vs,I_sof,I_eol,
 input wire[10:0] I_x,input wire[9:0] I_y,input wire[31:0] I_frame_id,input wire I_frame_valid,
 input wire[2:0] I_mode,input wire[1:0] I_level,input wire I_wb,
 input wire I_region_valid,input wire[10:0] I_region_left,I_region_right,
 input wire[9:0] I_region_top,I_region_bottom,
 input wire I_latency_valid,input wire[31:0] I_latency_ms,I_analysis_count,I_underflow_count,I_drop_count,
 input wire I_stats_valid,input wire[31:0] I_latency_min,I_latency_avg,I_latency_max,I_repeat_count,
 input wire[9:0] I_display_fps,I_new_fps,
 input wire[1:0] I_zone,input wire[10:0] I_zone_left,I_zone_right,input wire[9:0] I_zone_top,I_zone_bottom,
 input wire I_arm,I_alarm,I_track_valid,input wire[1:0] I_track_state,
 input wire[10:0] I_track_x,I_track_left,I_track_right,input wire[9:0] I_track_y,I_track_top,I_track_bottom,
 input wire[2:0] I_track_direction,
 output wire[23:0] O_rgb,output wire O_de,O_hs,O_vs,O_sof,O_eol,
 output wire[10:0] O_x,output wire[9:0] O_y,output wire[31:0] O_frame_id,output wire O_frame_valid);
reg[82:0] packet0,packet1,packet2;
assign {O_frame_valid,O_frame_id,O_x,O_y,O_de,O_hs,O_vs,O_sof,O_eol,O_rgb}=packet2;
reg[2:0] mode;reg[1:0] level;reg wb,latency_valid,stats_valid;
reg[3:0] latency_over;reg[1:0] fps_over;
reg[31:0] display_count;reg[31:0] numbers[0:12];reg[23:0] decimal[0:13];
reg[1:0] zone,track_state;reg arm,alarm_on,track_valid;reg[2:0] direction;
reg[10:0] zleft,zright,tx,tleft,tright;reg[9:0] ztop,zbottom,ty,ttop,tbottom;
reg zone_hit1,track_hit1;
reg[47:0] zone_label;reg[39:0] track_label;
reg converting;reg[3:0] field;reg[5:0] bit_count;reg[31:0] binary;reg[23:0] bcd;
function[23:0] bcd_shift;input[23:0] value;input next_bit;reg[23:0] adjusted;integer d;begin
 adjusted=value;for(d=0;d<6;d=d+1)if(value[d*4+:4]>=5)adjusted[d*4+:4]=value[d*4+:4]+3;
 bcd_shift={adjusted[22:0],next_bit};end endfunction
wire[23:0] bcd_next=bcd_shift(bcd,binary[31-bit_count]);
reg[7:0] character;reg[255:0] text;reg[5:0] char_index;reg[2:0] line_index;reg[8:0] text_y;
reg[3:0] font_row0,font_col0,font_col1;reg[7:0] font_char0;
wire[15:0] font_bits;reg[15:0] font_bits1;
reg text_hit0,text_hit1,logo_hit0,logo_hit1,box_hit1;
reg region_valid;reg[10:0] rleft,rright;reg[9:0] rtop,rbottom;
reg[14:0] logo_addr0;wire[24:0] logo_pixel;
osd_char_lib font(font_char0,font_row0,font_bits);
anlogic_logo_rom logo(I_clk,logo_addr0,logo_pixel);
function[7:0] digit;input[23:0] value;input[2:0] index;begin digit=8'h30+((value>>((5-index)*4))&4'hf);end endfunction
function[7:0] value4;input[23:0] value;input[1:0] index;input valid,overflow;begin
 if(!valid)case(index)0:value4="N";1:value4="A";default:value4=" ";endcase
 else if(overflow)case(index)0:value4="O";1:value4="V";2:value4="F";default:value4=" ";endcase
 else value4=digit(value,{1'b0,index}+3'd2);
end endfunction
function[7:0] value3;input[23:0] value;input[1:0] index;input overflow;begin
 if(overflow)case(index)0:value3="O";1:value3="V";default:value3="F";endcase
 else value3=digit(value,{1'b0,index}+3'd3);
end endfunction
always @*begin
 text_y=I_y-16;line_index=text_y[7:5];char_index=(I_x-192)>>4;
 text="                                ";character=8'h20;
 case(line_index)
  0:text="ANLOGIC HX1P35A                 ";
  1:text="MODE: COL TH: 1 WB: OFF         ";
  2:text="LAT: 0000 AVG:0000 MAX:0000 MS  ";
  3:text="CAP: 000000 DSP: 000000 FPS:000 ";
  4:text="ANL: 000000 UF: 000000 NEW:000  ";
  5:text="DROP: 000000 MIN:0000 REP:000000";
  6:text="ZONE: CENTER ARM:OFF ALM:IDLE   ";
  7:text="RED:LOST  X:0000 Y:0000 DIR:S   ";
 endcase
 if(char_index<32)character=text[255-char_index*8-:8];
 if(line_index==1)begin
  if(char_index>=6&&char_index<=8)case(mode)
   0:case(char_index)6:character="C";7:character="O";8:character="L";endcase
   1:case(char_index)6:character="G";7:character="R";8:character="Y";endcase
   2:case(char_index)6:character="B";7:character="I";8:character="N";endcase
   3:case(char_index)6:character="E";7:character="D";8:character="G";endcase
   4:case(char_index)6:character="O";7:character="V";8:character="L";endcase
   5:case(char_index)6:character="M";7:character="O";8:character="T";endcase
   6:case(char_index)6:character="T";7:character="R";8:character="K";endcase
  endcase
  if(char_index==14)character="0"+level;
  if(char_index>=20&&char_index<=22)case(char_index)20:character="O";21:character=wb?"N":"F";22:character=wb?" ":"F";endcase
 end
 if(line_index==2)begin
  if(char_index>=5&&char_index<=8)character=value4(decimal[0],char_index-5,latency_valid,latency_over[0]);
  if(char_index>=14&&char_index<=17)character=value4(decimal[8],char_index-14,stats_valid,latency_over[1]);
  if(char_index>=23&&char_index<=26)character=value4(decimal[9],char_index-23,stats_valid,latency_over[2]);
 end
 if(line_index==3)begin
  if(char_index>=5&&char_index<=10)character=digit(decimal[1],char_index-5);
  if(char_index>=17&&char_index<=22)character=digit(decimal[2],char_index-17);
  if(char_index>=28&&char_index<=30)character=value3(decimal[11],char_index-28,fps_over[0]);
 end
 if(line_index==4)begin
  if(char_index>=5&&char_index<=10)character=digit(decimal[3],char_index-5);
  if(char_index>=16&&char_index<=21)character=digit(decimal[4],char_index-16);
  if(char_index>=27&&char_index<=29)character=value3(decimal[12],char_index-27,fps_over[1]);
 end
 if(line_index==5)begin
  if(char_index>=6&&char_index<=11)character=digit(decimal[5],char_index-6);
  if(char_index>=17&&char_index<=20)character=value4(decimal[10],char_index-17,stats_valid,latency_over[3]);
  if(char_index>=26&&char_index<=31)character=digit(decimal[13],char_index-26);
 end
 case(zone)0:zone_label="FULL  ";1:zone_label="CENTER";2:zone_label="LEFT  ";default:zone_label="RIGHT ";endcase
 case(track_state)1:track_label="TRACK";2:track_label="HOLD ";default:track_label="LOST ";endcase
 if(line_index==6)begin
  if(char_index>=6&&char_index<=11)character=zone_label[47-(char_index-6)*8-:8];
  if(char_index==17)character="O";
  if(char_index==18)character=arm?"N":"F";
  if(char_index==19)character=arm?" ":"F";
  if(char_index>=25&&char_index<=29)case(char_index)
   25:character=alarm_on?"A":"I";26:character=alarm_on?"L":"D";27:character=alarm_on?"A":"L";
   28:character=alarm_on?"R":"E";29:character=alarm_on?"M":" ";endcase
 end
 if(line_index==7)begin
  if(char_index>=4&&char_index<=8)character=track_label[39-(char_index-4)*8-:8];
  if(char_index>=12&&char_index<=15)character=digit(decimal[6],char_index-10);
  if(char_index>=19&&char_index<=22)character=digit(decimal[7],char_index-17);
  if(char_index==28)case(direction)1:character="L";2:character="R";3:character="U";4:character="D";default:character="S";endcase
 end
end
integer j;
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin packet0<=0;packet1<=0;packet2<=0;mode<=0;level<=1;wb<=0;
  display_count<=0;latency_valid<=0;stats_valid<=0;latency_over<=0;fps_over<=0;region_valid<=0;rleft<=0;rright<=0;rtop<=0;rbottom<=0;
  converting<=0;field<=0;bit_count<=0;binary<=0;bcd<=0;font_char0<=0;font_row0<=0;font_col0<=0;font_col1<=0;
  font_bits1<=0;text_hit0<=0;text_hit1<=0;logo_hit0<=0;logo_hit1<=0;logo_addr0<=0;
  box_hit1<=0;
  zone<=0;arm<=0;alarm_on<=0;track_valid<=0;track_state<=0;direction<=0;
  zleft<=0;zright<=0;ztop<=0;zbottom<=0;tx<=0;ty<=0;tleft<=0;tright<=0;ttop<=0;tbottom<=0;
  zone_hit1<=0;track_hit1<=0;
  for(j=0;j<13;j=j+1)numbers[j]<=0;
  for(j=0;j<14;j=j+1)decimal[j]<=0;
 end else begin
  if(I_sof)begin
   mode<=I_mode;level<=I_level;wb<=I_wb;
   zone<=I_zone;arm<=I_arm;alarm_on<=I_alarm;track_valid<=I_track_valid;track_state<=I_track_state;
   zleft<=I_zone_left;zright<=I_zone_right;ztop<=I_zone_top;zbottom<=I_zone_bottom;
   tx<=I_track_x;ty<=I_track_y;tleft<=I_track_left;tright<=I_track_right;ttop<=I_track_top;tbottom<=I_track_bottom;
   direction<=I_track_direction;
   region_valid<=I_region_valid;rleft<=I_region_left;rright<=I_region_right;
   rtop<=I_region_top;rbottom<=I_region_bottom;
   display_count<=display_count+1'b1;latency_valid<=I_latency_valid;
   stats_valid<=I_stats_valid;
   latency_over<={I_latency_min>9999,I_latency_max>9999,I_latency_avg>9999,I_latency_ms>9999};
   fps_over<={I_new_fps>999,I_display_fps>999};
   numbers[0]<={1'b0,I_frame_id[30:0]};numbers[1]<=display_count+1'b1;
   numbers[2]<=I_analysis_count;numbers[3]<=I_underflow_count;numbers[4]<=I_drop_count;
   numbers[5]<=I_track_valid?{21'd0,I_track_x}:32'd0;numbers[6]<=I_track_valid?{22'd0,I_track_y}:32'd0;
   numbers[7]<=I_latency_avg;numbers[8]<=I_latency_max;numbers[9]<=I_latency_min;
   numbers[10]<={22'd0,I_display_fps};numbers[11]<={22'd0,I_new_fps};numbers[12]<=I_repeat_count;
   converting<=1;field<=0;bit_count<=0;binary<=I_latency_ms;bcd<=0;
  end else if(converting)begin
   bcd<=bcd_next;
   if(bit_count==31)begin
    decimal[field]<=bcd_next;bit_count<=0;bcd<=0;
    if(field==13)converting<=0;
    else begin field<=field+1'b1;binary<=numbers[field];end
   end else bit_count<=bit_count+1'b1;
  end
  packet0<={I_frame_valid,I_frame_id,I_x,I_y,I_de,I_hs,I_vs,I_sof,I_eol,I_rgb};packet1<=packet0;packet2<=packet1;
  font_char0<=character;font_row0<=text_y[3:0];font_col0<=I_x[3:0];font_col1<=font_col0;font_bits1<=font_bits;
  text_hit0<=I_de&&I_x>=192&&I_x<704&&I_y>=16&&I_y<272&&!text_y[4];text_hit1<=text_hit0;
  logo_hit0<=I_de&&I_x>=16&&I_x<176&&I_y>=16&&I_y<176;logo_hit1<=logo_hit0;
  // Hold ROM address outside the logo window to avoid needless ROM activity.
  if(I_de&&I_x>=16&&I_x<176&&I_y>=16&&I_y<176)logo_addr0<=(I_y-16)*160+(I_x-16);

  box_hit1<=packet0[28]&&mode==5&&region_valid&&packet0[49:39]>=rleft&&packet0[49:39]<=rright&&packet0[38:29]>=rtop&&packet0[38:29]<=rbottom&&
   (packet0[49:39]<=rleft+1||packet0[49:39]+1>=rright||packet0[38:29]<=rtop+1||packet0[38:29]+1>=rbottom);
  zone_hit1<=packet0[28]&&mode==5&&packet0[49:39]>=zleft&&packet0[49:39]<=zright&&packet0[38:29]>=ztop&&packet0[38:29]<=zbottom&&
   (packet0[49:39]==zleft||packet0[49:39]==zright||packet0[38:29]==ztop||packet0[38:29]==zbottom);
  track_hit1<=packet0[28]&&mode==6&&track_valid&&(
   (packet0[49:39]>=tleft&&packet0[49:39]<=tright&&packet0[38:29]>=ttop&&packet0[38:29]<=tbottom&&(packet0[49:39]<=tleft+1||packet0[49:39]+1>=tright||packet0[38:29]<=ttop+1||packet0[38:29]+1>=tbottom))||
   (packet0[38:29]==ty&&packet0[49:39]+6>=tx&&packet0[49:39]<=tx+6)||(packet0[49:39]==tx&&packet0[38:29]+6>=ty&&packet0[38:29]<=ty+6));
  if(logo_hit1&&logo_pixel[24])packet2[23:0]<=logo_pixel[23:0];
  else if(text_hit1)packet2[23:0]<=font_bits1[15-font_col1]?24'hffffff:24'h101828;
  else if(track_hit1)packet2[23:0]<=track_state==2?24'hffb020:24'h00ff40;
  else if(box_hit1)packet2[23:0]<=24'hffb020;
  else if(zone_hit1)packet2[23:0]<=24'h0080ff;
 end
end
endmodule

