`timescale 1ns/1ps
module hdmi_mixer #(parameter H_OFFSET=0,V_OFFSET=0,IMG_WIDTH=1280,IMG_HEIGHT=720,H_TOTAL=1650,DEBUG_MODE=0)(
 input wire I_clk,I_rst_n,I_video_vsync,I_video_hsync,I_video_de,I_video_user,I_video_last,
 input wire[3:0] I_debug_status,input wire[2:0] I_video_mode,output wire O_video_rd_en,
 input wire[23:0] I_video_rd_data,output wire O_hdmi_vsync,O_hdmi_hsync,O_hdmi_de,output wire[23:0] O_hdmi_data,
 input wire[1:0] I_level,input wire I_wb,input wire[10:0] I_x,input wire[9:0] I_y,
 input wire[31:0] I_frame_id,input wire I_frame_valid,input wire[47:0] I_capture_tick,I_now_tick,
 input wire[31:0] I_drop_count,I_underflow_count,
 input wire I_arm,output wire O_buzzer_n,output wire O_led,input wire[1:0] I_zone);
assign O_video_rd_en=I_video_de;
wire[82:0] awb_packet,processed,output_packet;
wire[10:0] query_x;wire[9:0] query_y;wire motion;
wire[10:0] zone_left,zone_right;wire[9:0] zone_top,zone_bottom;
zone_bounds #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) zone_limits(I_zone,zone_left,zone_right,zone_top,zone_bottom);
reg source;reg[1:0] previous_zone;
// Manual controls remain meaningful during blank/torn frames; source IDs do not.
wire clear=I_video_user&&((previous_zone!=I_zone)||(I_frame_valid&&source!=I_frame_id[31]));
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin source<=0;previous_zone<=1;end
 else if(I_video_user)begin previous_zone<=I_zone;if(I_frame_valid)source<=I_frame_id[31];end
end
wire result,candidate,scene,analysis_busy;wire[31:0] result_id,analysis_count;
wire[10:0] region_left,region_right;wire[9:0] region_top,region_bottom,region_area;
wire[13:0] strong_count;
wire armed,alarm_on;
reg motion_box_valid;reg[10:0] motion_left,motion_right;reg[9:0] motion_top,motion_bottom;
reg[1:0] motion_misses;reg[5:0] motion_stale;
// Update at every new result, without the alarm's separate strong-change gate.
// Keep two missed results to avoid flashing; never keep a frozen box indefinitely.
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin motion_box_valid<=0;motion_left<=0;motion_right<=0;motion_top<=0;motion_bottom<=0;motion_misses<=0;motion_stale<=0;end
 else if(clear)begin motion_box_valid<=0;motion_misses<=0;motion_stale<=0;end
 else begin
  if(I_video_user)begin
   if(motion_stale<30)motion_stale<=motion_stale+1'b1;
   if(motion_stale>=29)motion_box_valid<=0;
  end
  if(result)begin
   motion_stale<=0;
   if(scene)begin motion_box_valid<=0;motion_misses<=0;end
   else if(candidate)begin
    motion_box_valid<=1;motion_misses<=0;motion_left<=region_left;motion_right<=region_right;
    motion_top<=region_top;motion_bottom<=region_bottom;
   end else if(motion_misses==2)motion_box_valid<=0;
   else motion_misses<=motion_misses+1'b1;
  end
 end
end
wire[7:0] motion_threshold=I_level==0?8:I_level==2?20:12;
motion_regions #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT),.ENABLE_ZONE(1),.SAMPLE_SHIFT(2),
 .CELL_HITS(3),.MIN_AREA(1),.PRECISE_BOX(1),.BOX_MARGIN(12),.SCENE_PERCENT(85),.WEAK_GROW(1),.MAP_RAM(1)) regions(.I_clk(I_clk),.I_rst_n(I_rst_n),
 .I_rgb(I_video_rd_data),.I_de(I_video_de),.I_sof(I_video_user),.I_eol(I_video_last),.I_x(I_x),.I_y(I_y),
 .I_frame_id(I_frame_id),.I_frame_valid(I_frame_valid),.I_threshold(motion_threshold),.I_clear(clear),
 .I_track_active(1'b0),.I_target_x(11'd0),.I_target_y(10'd0),.I_target_area(10'd0),
 .I_grid_x(query_x[10:5]),.I_grid_y(query_y[9:5]),.O_grid_motion(motion),
 .O_result_valid(result),.O_candidate_valid(candidate),.O_scene_change(scene),.O_result_frame_id(result_id),
 .O_left(region_left),.O_right(region_right),.O_top(region_top),.O_bottom(region_bottom),.O_area(region_area),
 .O_busy(analysis_busy),.O_analysis_count(analysis_count),.O_strong_count(strong_count),
 .I_zone_left(zone_left),.I_zone_right(zone_right),.I_zone_top(zone_top),.I_zone_bottom(zone_bottom));
digital_awb #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) awb(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_rgb(I_video_rd_data),
 .I_de(I_video_de),.I_hs(I_video_hsync),.I_vs(I_video_vsync),.I_sof(I_video_user),.I_eol(I_video_last),
 .I_x(I_x),.I_y(I_y),.I_frame_id(I_frame_id),.I_frame_valid(I_frame_valid),.I_enable(I_wb),
 .O_rgb(awb_packet[23:0]),.O_de(awb_packet[28]),.O_hs(awb_packet[27]),.O_vs(awb_packet[26]),
 .O_sof(awb_packet[25]),.O_eol(awb_packet[24]),.O_x(awb_packet[49:39]),.O_y(awb_packet[38:29]),
 .O_frame_id(awb_packet[81:50]),.O_frame_valid(awb_packet[82]),.O_gain_r(),.O_gain_g(),.O_gain_b());
wire track_valid;wire[1:0] track_state;wire[2:0] track_direction;
wire[10:0] track_x,track_left,track_right;wire[9:0] track_y,track_top,track_bottom;
reg track_source,track_wb;
wire track_clear=awb_packet[25]&&((track_wb!=I_wb)||(awb_packet[82]&&track_source!=awb_packet[81]));
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin track_source<=0;track_wb<=0;end
 else if(awb_packet[25])begin track_wb<=I_wb;if(awb_packet[82])track_source<=awb_packet[81];end
end
color_tracker #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) tracker(.I_clk(I_clk),.I_rst_n(I_rst_n),
 .I_rgb(awb_packet[23:0]),.I_de(awb_packet[28]),.I_sof(awb_packet[25]),.I_eol(awb_packet[24]),
 .I_x(awb_packet[49:39]),.I_y(awb_packet[38:29]),.I_frame_id(awb_packet[81:50]),.I_frame_valid(awb_packet[82]),
 .I_clear(track_clear),.O_valid(track_valid),.O_state(track_state),.O_x(track_x),.O_y(track_y),
 .O_left(track_left),.O_right(track_right),.O_top(track_top),.O_bottom(track_bottom),.O_direction(track_direction));
pixel_pipeline #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT),.H_TOTAL(H_TOTAL)) effects(.I_clk(I_clk),.I_rst_n(I_rst_n),
 .I_rgb(awb_packet[23:0]),.I_de(awb_packet[28]),.I_hs(awb_packet[27]),.I_vs(awb_packet[26]),
 .I_sof(awb_packet[25]),.I_eol(awb_packet[24]),.I_x(awb_packet[49:39]),.I_y(awb_packet[38:29]),
 .I_frame_id(awb_packet[81:50]),.I_frame_valid(awb_packet[82]),.I_mode(I_video_mode),.I_level(I_level),.I_motion(motion),
 .O_rgb(processed[23:0]),.O_de(processed[28]),.O_hs(processed[27]),.O_vs(processed[26]),
 .O_sof(processed[25]),.O_eol(processed[24]),.O_x(processed[49:39]),.O_y(processed[38:29]),
 .O_frame_id(processed[81:50]),.O_frame_valid(processed[82]),.O_query_x(query_x),.O_query_y(query_y));
wire latency_valid;wire[31:0] latency_ms;
// Timestamp the actual OSD output SOF at the HDMI core input boundary.
frame_latency latency(I_clk,I_rst_n,output_packet[25],output_packet[82],I_capture_tick,I_now_tick,latency_valid,latency_ms);
wire stats_valid;wire[31:0] latency_min,latency_avg,latency_max,repeat_count;
wire[9:0] display_fps,new_fps;
video_metrics metrics(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_sof(output_packet[25]),
 .I_frame_valid(output_packet[82]),.I_frame_id(output_packet[81:50]),
 .I_latency_valid(latency_valid),.I_latency_ms(latency_ms),.O_stats_valid(stats_valid),
 .O_latency_min(latency_min),.O_latency_avg(latency_avg),.O_latency_max(latency_max),
 .O_display_fps(display_fps),.O_new_fps(new_fps),.O_repeat_count(repeat_count));
video_osd osd(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_rgb(processed[23:0]),.I_de(processed[28]),.I_hs(processed[27]),.I_vs(processed[26]),
 .I_sof(processed[25]),.I_eol(processed[24]),.I_x(processed[49:39]),.I_y(processed[38:29]),
 .I_frame_id(processed[81:50]),.I_frame_valid(processed[82]),.I_mode(I_video_mode),.I_level(I_level),.I_wb(I_wb),
 .I_region_valid(motion_box_valid),.I_region_left(motion_left),.I_region_right(motion_right),
 .I_region_top(motion_top),.I_region_bottom(motion_bottom),
 .I_zone(I_zone),.I_zone_left(zone_left),.I_zone_right(zone_right),.I_zone_top(zone_top),.I_zone_bottom(zone_bottom),
 .I_arm(armed),.I_alarm(alarm_on),.I_track_valid(track_valid),.I_track_state(track_state),
 .I_track_x(track_x),.I_track_y(track_y),.I_track_left(track_left),.I_track_right(track_right),
 .I_track_top(track_top),.I_track_bottom(track_bottom),.I_track_direction(track_direction),
 .I_latency_valid(latency_valid),.I_latency_ms(latency_ms),
 .I_stats_valid(stats_valid),.I_latency_min(latency_min),.I_latency_avg(latency_avg),.I_latency_max(latency_max),
 .I_repeat_count(repeat_count),.I_display_fps(display_fps),.I_new_fps(new_fps),
 .I_analysis_count(analysis_count),.I_underflow_count(I_underflow_count),.I_drop_count(I_drop_count),
 .O_rgb(output_packet[23:0]),.O_de(output_packet[28]),.O_hs(output_packet[27]),.O_vs(output_packet[26]),
 .O_sof(output_packet[25]),.O_eol(output_packet[24]),.O_x(output_packet[49:39]),.O_y(output_packet[38:29]),
 .O_frame_id(output_packet[81:50]),.O_frame_valid(output_packet[82]));
intrusion_alarm alarm(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_arm(I_arm),
 .I_result(result),.I_result_id(result_id),.I_clear(clear),.I_candidate(candidate),.I_scene(scene),.I_area(region_area),
 .I_strong(strong_count),.O_alarm(alarm_on),.O_armed(armed),.O_buzzer_n(O_buzzer_n),.O_led(O_led));
assign O_hdmi_data=output_packet[23:0];assign O_hdmi_de=output_packet[28];
assign O_hdmi_hsync=output_packet[27];assign O_hdmi_vsync=output_packet[26];
endmodule

