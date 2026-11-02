`timescale 1ns/1ps
module motion_regions #(parameter WIDTH=1280,HEIGHT=720,ENABLE_ZONE=0,
 parameter SAMPLE_SHIFT=3,CELL_HITS=4,MIN_AREA=3,PRECISE_BOX=0,BOX_MARGIN=32,SCENE_PERCENT=40,
 parameter WEAK_GROW=0,WEAK_HITS=6,MAP_RAM=0)(
 input wire I_clk,I_rst_n,input wire[23:0] I_rgb,input wire I_de,I_sof,I_eol,
 input wire[10:0] I_x,input wire[9:0] I_y,input wire[31:0] I_frame_id,input wire I_frame_valid,
 input wire[7:0] I_threshold,input wire I_clear,I_track_active,
 input wire[10:0] I_target_x,input wire[9:0] I_target_y,I_target_area,
 input wire[5:0] I_grid_x,input wire[4:0] I_grid_y,output wire O_grid_motion,
 output reg O_result_valid,O_candidate_valid,O_scene_change,output reg[31:0] O_result_frame_id,
 output reg[10:0] O_left,O_right,output reg[9:0] O_top,O_bottom,O_area,
 output wire O_busy,output reg[31:0] O_analysis_count,
 input wire[10:0] I_zone_left,I_zone_right,input wire[9:0] I_zone_top,I_zone_bottom,
 output reg[13:0] O_strong_count);
localparam STEP=1<<SAMPLE_SHIFT,PER_CELL=32/STEP;
localparam SW=WIDTH/STEP,SH=HEIGHT/STEP,GW=(WIDTH+31)/32,GH=(HEIGHT+31)/32,CELLS=GW*GH;
// All operands are nonnegative integers. Compare counts to constant floors:
// n*100 > total*p iff n > floor(total*p/100), and <= likewise.
// Keep the original strict scene boundary without a live multiply at EOF.
localparam SCENE_CELL_LIMIT=(CELLS*SCENE_PERCENT)/100,WEAK_CELL_LIMIT=(CELLS*60)/100;
localparam HIT_WIDTH=$clog2(PER_CELL*PER_CELL+1);
localparam LOCAL_BITS=5-SAMPLE_SHIFT,BOUND_BITS=4*LOCAL_BITS;
localparam SAMPLE_ADDR_WIDTH=$clog2(SW*SH);
(* ram_style="bram" *) reg[7:0] previous[0:SW*SH-1];
// Raster traversal only needs the current grid row's accumulators.
reg[HIT_WIDTH-1:0] hits[0:GW-1];reg[5:0] hit_col;
// Only current grid-row extrema are registers. Completed cells use one RAM.
reg[LOCAL_BITS-1:0] xmin[0:GW-1],xmax[0:GW-1],ymin[0:GW-1],ymax[0:GW-1];
(* ram_style="bram" *)reg[BOUND_BITS-1:0] cell_bounds[0:CELLS-1];
reg[BOUND_BITS-1:0] bounds_read;reg[4:0] local_xd,local_yd;reg[10:0] queue_data;
reg[CELLS-1:0] motion_map,support_map,display_map,render_map;
// Analysis RAM is overwritten once per cell by every complete capture. It has
// no whole-array reset; torn captures never enter BFS and bootstrap again.
(* ram_style="bram" *)reg[1:0] analysis_map[0:CELLS-1];
reg[1:0] analysis_map_read;
reg[HIT_WIDTH-1:0] weak_hits[0:GW-1];
(* ram_style="bram" *)reg visited[0:CELLS-1];
reg visited_read,map_read_legacy,clear_active;reg[9:0] clear_addr;
reg capture,have_reference,observed,grow_frame;reg[31:0] last_id,analysis_id;
reg[3:0] state;assign O_busy=state!=0;
wire map_read=MAP_RAM?analysis_map_read[(WEAK_GROW&&grow_frame&&state==9)?1:0]:map_read_legacy;
wire new_id=!observed||I_frame_id!=last_id;
wire start=I_sof&&I_frame_valid&&new_id&&!O_busy;
wire sample=I_de&&I_frame_valid&&(capture||start)&&(I_x&(STEP-1))==0&&(I_y&(STEP-1))==0;
wire[SAMPLE_ADDR_WIDTH-1:0] sample_addr=(I_y>>SAMPLE_SHIFT)*SW+(I_x>>SAMPLE_SHIFT);
wire[9:0] cell_addr=(I_y>>5)*GW+(I_x>>5);
wire[15:0] gray_sum=I_rgb[23:16]*16'd77+I_rgb[15:8]*16'd150+I_rgb[7:0]*16'd29;
reg sample_d,first_d,last_d,zone_d;reg[9:0] cell_d;reg[7:0] prior,gray_d;reg[HIT_WIDTH-1:0] required_d,weak_required_d;
wire[10:0] zone_left=ENABLE_ZONE?I_zone_left:0,zone_right=ENABLE_ZONE?I_zone_right:WIDTH-1;
wire[9:0] zone_top=ENABLE_ZONE?I_zone_top:0,zone_bottom=ENABLE_ZONE?I_zone_bottom:HEIGHT-1;
wire sample_in_zone=I_x>=zone_left&&I_x<=zone_right&&I_y>=zone_top&&I_y<=zone_bottom;
wire[8:0] diff=gray_d>=prior?{1'b0,gray_d}-{1'b0,prior}:{1'b0,prior}-{1'b0,gray_d};
wire changed=have_reference&&diff>=I_threshold;
wire[7:0] support_threshold=(I_threshold>>1)<6?8'd6:(I_threshold>>1);
wire weak_changed=have_reference&&diff>=support_threshold;
wire bound_changed=changed||(WEAK_GROW&&weak_changed);
wire[HIT_WIDTH-1:0] updated=(first_d?{HIT_WIDTH{1'b0}}:hits[hit_col])+changed;
wire[HIT_WIDTH-1:0] weak_updated=(first_d?{HIT_WIDTH{1'b0}}:weak_hits[hit_col])+weak_changed;
wire[LOCAL_BITS-1:0] local_sx=local_xd[4:SAMPLE_SHIFT],local_sy=local_yd[4:SAMPLE_SHIFT];
wire[LOCAL_BITS-1:0] base_xmin=first_d?{LOCAL_BITS{1'b1}}:xmin[hit_col],base_xmax=first_d?{LOCAL_BITS{1'b0}}:xmax[hit_col];
wire[LOCAL_BITS-1:0] base_ymin=first_d?{LOCAL_BITS{1'b1}}:ymin[hit_col],base_ymax=first_d?{LOCAL_BITS{1'b0}}:ymax[hit_col];
wire[LOCAL_BITS-1:0] next_xmin=bound_changed&&local_sx<base_xmin?local_sx:base_xmin;
wire[LOCAL_BITS-1:0] next_xmax=bound_changed&&local_sx>base_xmax?local_sx:base_xmax;
wire[LOCAL_BITS-1:0] next_ymin=bound_changed&&local_sy<base_ymin?local_sy:base_ymin;
wire[LOCAL_BITS-1:0] next_ymax=bound_changed&&local_sy>base_ymax?local_sy:base_ymax;
reg[9:0] motion_cells,weak_cells;
wire strong_cell=updated>=required_d;
wire support_cell=strong_cell||weak_updated>=weak_required_d;
wire[10:0] final_motion_cells={1'b0,motion_cells}+(sample_d&&last_d&&strong_cell);
wire[10:0] final_weak_cells={1'b0,weak_cells}+(sample_d&&last_d&&support_cell);
assign O_grid_motion=I_grid_x<GW&&I_grid_y<GH?render_map[I_grid_y*GW+I_grid_x]:1'b0;
reg[SAMPLE_ADDR_WIDTH-1:0] sample_addr_d;
wire[8:0] bg_diff=gray_d>=prior?{1'b0,gray_d}-{1'b0,prior}:{1'b0,prior}-{1'b0,gray_d};
wire[7:0] bg_step_base=(bg_diff+9'd8)>>4;
// Weak support can be below the old 7-level rounding dead band. Let supported
// changes converge by one level there so stale weak regions do not persist.
wire[7:0] bg_step=WEAK_GROW&&bg_step_base==0&&bound_changed&&bg_diff!=0?8'd1:bg_step_base;
wire[7:0] bg_next=gray_d>=prior?prior+bg_step:prior-bg_step;
// Adaptive background: first frame after reset/clear bootstraps raw, then converges at 1/16 per frame.
always @(posedge I_clk)begin
 if(sample&&!I_clear)begin prior<=previous[sample_addr];sample_addr_d<=sample_addr;end
 if(sample_d&&!I_clear)previous[sample_addr_d]<=have_reference?bg_next:gray_d;
 if(PRECISE_BOX&&sample_d&&!I_clear)begin
  xmin[hit_col]<=next_xmin;xmax[hit_col]<=next_xmax;ymin[hit_col]<=next_ymin;ymax[hit_col]<=next_ymax;
  if(last_d)cell_bounds[cell_d]<={next_xmin,next_xmax,next_ymin,next_ymax};
 end
 if(PRECISE_BOX&&state==3)bounds_read<=cell_bounds[queue_data[10:6]*GW+queue_data[5:0]];
 if(MAP_RAM&&I_rst_n&&!I_clear&&sample_d&&last_d)
  analysis_map[cell_d]<={(WEAK_GROW?support_cell:strong_cell)&&zone_d,strong_cell&&zone_d};
end
(* ram_style="bram" *) reg[10:0] queue[0:CELLS-1];
reg[9:0] head,tail,scan;
reg[5:0] scan_col,current_col,min_col,max_col;reg[4:0] scan_row,current_row,min_row,max_row;
reg[2:0] neighbor;reg[9:0] area;reg[9:0] best_area;reg[11:0] best_distance;
wire[2:0] last_neighbor=(WEAK_GROW&&grow_frame)?3'd7:3'd3;
reg[10:0] best_left,best_right;reg[9:0] best_top,best_bottom;
// Union bounding box across all acceptable regions (covers one object split into blobs).
reg union_found;reg[5:0] uni_min_col,uni_max_col;reg[4:0] uni_min_row,uni_max_row;
reg[10:0] pixel_min_x,pixel_max_x,uni_pixel_min_x,uni_pixel_max_x;
reg[9:0] pixel_min_y,pixel_max_y,uni_pixel_min_y,uni_pixel_max_y;
reg[5:0] nc;reg[4:0] nr;reg neighbor_valid;reg[9:0] neighbor_addr;
always @*begin
 nc=current_col;nr=current_row;neighbor_valid=1;
 case(neighbor)
  0:if(current_col==0)neighbor_valid=0;else nc=current_col-1'b1;
  1:if(current_col==GW-1)neighbor_valid=0;else nc=current_col+1'b1;
  2:if(current_row==0)neighbor_valid=0;else nr=current_row-1'b1;
  3:if(current_row==GH-1)neighbor_valid=0;else nr=current_row+1'b1;
  4:if(current_col==0||current_row==0)neighbor_valid=0;else begin nc=current_col-1'b1;nr=current_row-1'b1;end
  5:if(current_col==GW-1||current_row==0)neighbor_valid=0;else begin nc=current_col+1'b1;nr=current_row-1'b1;end
  6:if(current_col==0||current_row==GH-1)neighbor_valid=0;else begin nc=current_col-1'b1;nr=current_row+1'b1;end
  7:if(current_col==GW-1||current_row==GH-1)neighbor_valid=0;else begin nc=current_col+1'b1;nr=current_row+1'b1;end
 endcase
 neighbor_addr=nr*GW+nc;
end
wire[11:0] raw_right=({6'd0,max_col}+12'd1)*32-1;
wire[10:0] raw_bottom=({6'd0,max_row}+11'd1)*32-1;
wire[10:0] candidate_left=min_col==0?0:min_col*32-16;
wire[10:0] candidate_right=raw_right+16>=WIDTH?WIDTH-1:raw_right+16;
wire[9:0] candidate_top=min_row==0?0:min_row*32-16;
wire[9:0] candidate_bottom=raw_bottom+16>=HEIGHT?HEIGHT-1:raw_bottom+16;
wire[11:0] cx_sum={1'b0,candidate_left}+{1'b0,candidate_right};
wire[10:0] cy_sum={1'b0,candidate_top}+{1'b0,candidate_bottom};
// Union box in pixel coords with 32px margin, clamped to the frame.
wire[10:0] precise_left=uni_pixel_min_x>BOX_MARGIN?uni_pixel_min_x-BOX_MARGIN:0;
wire[10:0] precise_right=uni_pixel_max_x+BOX_MARGIN>=WIDTH?WIDTH-1:uni_pixel_max_x+BOX_MARGIN;
wire[9:0] precise_top=uni_pixel_min_y>BOX_MARGIN?uni_pixel_min_y-BOX_MARGIN:0;
wire[9:0] precise_bottom=uni_pixel_max_y+BOX_MARGIN>=HEIGHT?HEIGHT-1:uni_pixel_max_y+BOX_MARGIN;
wire[4:0] bound_left={bounds_read[BOUND_BITS-1-:LOCAL_BITS],{SAMPLE_SHIFT{1'b0}}};
wire[4:0] bound_right={bounds_read[3*LOCAL_BITS-1-:LOCAL_BITS],{SAMPLE_SHIFT{1'b0}}};
wire[4:0] bound_top={bounds_read[2*LOCAL_BITS-1-:LOCAL_BITS],{SAMPLE_SHIFT{1'b0}}};
wire[4:0] bound_bottom={bounds_read[LOCAL_BITS-1:0],{SAMPLE_SHIFT{1'b0}}};
wire[10:0] cell_pixel_left={current_col,5'b0}+bound_left;
wire[10:0] cell_pixel_right={current_col,5'b0}+bound_right+STEP-1;
wire[9:0] cell_pixel_top={current_row,5'b0}+bound_top;
wire[9:0] cell_pixel_bottom={current_row,5'b0}+bound_bottom+STEP-1;
wire[10:0] union_left=PRECISE_BOX?precise_left:uni_min_col<=1?11'd0:uni_min_col*32-32;
wire[11:0] union_raw_right=({6'd0,uni_max_col}+12'd1)*32-1;
wire[10:0] union_right=PRECISE_BOX?precise_right:union_raw_right+32>=WIDTH?WIDTH-1:union_raw_right+32;
wire[9:0] union_top=PRECISE_BOX?precise_top:uni_min_row<=1?10'd0:uni_min_row*32-32;
wire[10:0] union_raw_bottom=({6'd0,uni_max_row}+11'd1)*32-1;
wire[9:0] union_bottom=PRECISE_BOX?precise_bottom:union_raw_bottom+32>=HEIGHT?HEIGHT-1:union_raw_bottom+32;
wire[10:0] cx=cx_sum[11:1];wire[9:0] cy=cy_sum[10:1];
wire[11:0] distance=(cx>=I_target_x?cx-I_target_x:I_target_x-cx)+
 (cy>=I_target_y?cy-I_target_y:I_target_y-cy);
wire acceptable=area>=MIN_AREA&&(!I_track_active||(distance<=192&&area*4>=I_target_area&&area<=I_target_area*4));
wire scan_row_end=scan_col==zone_right[10:5];
wire last_scan=scan_row_end&&scan_row==zone_bottom[9:5];
wire[9:0] scan_step=scan_row_end?GW-({4'd0,zone_right[10:5]}-{4'd0,zone_left[10:5]}):10'd1;
wire[9:0] scan_next=scan+scan_step;
wire seed=state==8&&scan<CELLS&&map_read&&!visited_read;
wire enqueue=state==9&&neighbor_valid&&map_read&&!visited_read;
// One physical write port, shared between region seeding and BFS enqueue.
always @(posedge I_clk)if(I_rst_n&&!I_clear&&(seed||enqueue))
 queue[seed?10'd0:tail]<=seed?{scan_row,scan_col}:{nr,nc};
always @(posedge I_clk)if(state==2&&head<tail)queue_data<=queue[head];
// One physical read and write port; state selects each address before the RAM.
wire visited_read_en=(state==1&&scan<CELLS)||(state==8&&!last_scan)||state==4;
wire[9:0] visited_raddr=state==4?neighbor_addr:state==8?scan_next:scan;
wire visited_write_en=clear_active||seed||enqueue;
wire[9:0] visited_waddr=clear_active?clear_addr:seed?scan:neighbor_addr;
always @(posedge I_clk)begin
 if(visited_read_en)begin
  visited_read<=visited[visited_raddr];
  if(MAP_RAM)analysis_map_read<=analysis_map[visited_raddr];
  else map_read_legacy<=(WEAK_GROW&&grow_frame&&state==4)?support_map[visited_raddr]:motion_map[visited_raddr];
 end
 if(I_rst_n&&!I_clear&&visited_write_en)visited[visited_waddr]<=!clear_active;
end
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin capture<=0;have_reference<=0;observed<=0;last_id<=0;analysis_id<=0;state<=0;
  sample_d<=0;first_d<=0;last_d<=0;zone_d<=0;cell_d<=0;hit_col<=0;gray_d<=0;required_d<=0;weak_required_d<=0;O_strong_count<=0;
  motion_map<=0;support_map<=0;display_map<=0;render_map<=0;clear_addr<=0;clear_active<=0;motion_cells<=0;weak_cells<=0;grow_frame<=0;head<=0;tail<=0;scan<=0;scan_col<=0;scan_row<=0;
  current_col<=0;current_row<=0;min_col<=0;max_col<=0;min_row<=0;max_row<=0;neighbor<=0;area<=0;
  best_area<=0;best_distance<=4095;best_left<=0;best_right<=0;best_top<=0;best_bottom<=0;
  O_result_valid<=0;O_candidate_valid<=0;O_scene_change<=0;O_result_frame_id<=0;
  O_left<=0;O_right<=0;O_top<=0;O_bottom<=0;O_area<=0;O_analysis_count<=0;
  union_found<=0;uni_min_col<=0;uni_max_col<=0;uni_min_row<=0;uni_max_row<=0;
  pixel_min_x<=0;pixel_max_x<=0;pixel_min_y<=0;pixel_max_y<=0;
  uni_pixel_min_x<=0;uni_pixel_max_x<=0;uni_pixel_min_y<=0;uni_pixel_max_y<=0;local_xd<=0;local_yd<=0;
 end else if(I_clear)begin state<=0;capture<=0;have_reference<=0;observed<=0;sample_d<=0;
  motion_map<=0;support_map<=0;display_map<=0;render_map<=0;clear_addr<=0;clear_active<=0;motion_cells<=0;weak_cells<=0;grow_frame<=0;O_strong_count<=0;O_result_valid<=0;O_candidate_valid<=0;O_scene_change<=0;
 end else begin
  O_result_valid<=0;sample_d<=sample;
  if(clear_active)begin
   if(clear_addr==CELLS-1)clear_active<=0;else clear_addr<=clear_addr+1'b1;
  end
  if(I_sof)render_map<=display_map;
  // A torn/underflowed frame must not produce a motion result or reference.
  if(I_de&&!I_frame_valid)begin capture<=0;have_reference<=0;observed<=0;sample_d<=0;end
  if(I_sof&&I_frame_valid&&new_id)begin observed<=1;last_id<=I_frame_id;capture<=!O_busy;end
  if(start)begin clear_active<=1;clear_addr<=0;motion_map<=0;support_map<=0;motion_cells<=0;weak_cells<=0;O_strong_count<=0;analysis_id<=I_frame_id;end
  if(sample)begin
   gray_d<=gray_sum[15:8];cell_d<=cell_addr;hit_col<=I_x>>5;first_d<=I_x[4:0]==0&&I_y[4:0]==0;zone_d<=sample_in_zone;
   local_xd<=I_x[4:0];local_yd<=I_y[4:0];
   last_d<=(I_x[4:0]==32-STEP||(I_x>>SAMPLE_SHIFT)==SW-1)&&(I_y[4:0]==32-STEP||(I_y>>SAMPLE_SHIFT)==SH-1);
   // Scale the required support for the partial bottom grid row.
   required_d<=((I_y>>5)==GH-1&&SH%PER_CELL!=0)?(CELL_HITS*(SH%PER_CELL)+PER_CELL-1)/PER_CELL:CELL_HITS;
   weak_required_d<=((I_y>>5)==GH-1&&SH%PER_CELL!=0)?(WEAK_HITS*(SH%PER_CELL)+PER_CELL-1)/PER_CELL:WEAK_HITS;
  end
  if(sample_d)begin
   hits[hit_col]<=updated;
   if(WEAK_GROW)weak_hits[hit_col]<=weak_updated;
   // Alarm keeps its original 8x8 spatial count despite the denser display path.
   if(have_reference&&zone_d&&diff>=48&&(SAMPLE_SHIFT>=3||(local_xd[2:0]==0&&local_yd[2:0]==0))&&O_strong_count!=14'd16383)
    O_strong_count<=O_strong_count+1'b1;
   if(last_d)begin motion_map[cell_d]<=updated>=required_d&&zone_d;
    if(WEAK_GROW)support_map[cell_d]<=(updated>=required_d||weak_updated>=weak_required_d)&&zone_d;
    if(updated>=required_d)motion_cells<=motion_cells+1'b1;
    if(WEAK_GROW&&support_cell)weak_cells<=weak_cells+1'b1;
   end
  end
  if(capture&&I_frame_valid&&I_de&&I_eol&&I_y==HEIGHT-1)begin
   capture<=0;have_reference<=1;display_map<=motion_map;
   best_area<=0;best_distance<=4095;scan<=(zone_top>>5)*GW+(zone_left>>5);scan_col<=zone_left[10:5];scan_row<=zone_top[9:5];union_found<=0;
   // Widespread weak illumination/noise must not connect a torso to the whole frame.
   grow_frame<=WEAK_GROW&&final_weak_cells<=WEAK_CELL_LIMIT;
   if(final_motion_cells>SCENE_CELL_LIMIT)begin O_scene_change<=1;state<=6;end
   else begin O_scene_change<=0;state<=clear_active?7:1;end
  end
  case(state)
   7:if(!clear_active)state<=1;
   1:if(scan==CELLS)state<=6;else state<=8;
   8:begin
    if(map_read&&!visited_read)begin
     head<=0;tail<=1;area<=0;
     min_col<=scan_col;max_col<=scan_col;min_row<=scan_row;max_row<=scan_row;state<=2;
     pixel_min_x<=WIDTH-1;pixel_max_x<=0;pixel_min_y<=HEIGHT-1;pixel_max_y<=0;
    end else begin scan<=scan_next;state<=last_scan?6:8;if(scan_row_end)begin scan_col<=zone_left[10:5];scan_row<=scan_row+1'b1;end else scan_col<=scan_col+1'b1;end
   end
   2:if(head<tail)state<=3;else state<=5;
   3:begin
    current_col<=queue_data[5:0];current_row<=queue_data[10:6];head<=head+1'b1;area<=area+1'b1;neighbor<=0;state<=4;
    if(queue_data[5:0]<min_col)min_col<=queue_data[5:0];if(queue_data[5:0]>max_col)max_col<=queue_data[5:0];
    if(queue_data[10:6]<min_row)min_row<=queue_data[10:6];if(queue_data[10:6]>max_row)max_row<=queue_data[10:6];
   end
   4:begin
    state<=9;
    if(PRECISE_BOX&&neighbor==0)begin
     if(cell_pixel_left<pixel_min_x)pixel_min_x<=cell_pixel_left;
     if(cell_pixel_right>pixel_max_x)pixel_max_x<=cell_pixel_right;
     if(cell_pixel_top<pixel_min_y)pixel_min_y<=cell_pixel_top;
     if(cell_pixel_bottom>pixel_max_y)pixel_max_y<=cell_pixel_bottom;
    end
   end
   9:begin
    if(enqueue)tail<=tail+1'b1;
    if(neighbor==last_neighbor)state<=2;else begin neighbor<=neighbor+1'b1;state<=4;end
   end
   5:begin
    if(acceptable)begin
     if(!I_track_active?area>best_area:distance<best_distance)begin
      best_area<=area;best_distance<=distance;best_left<=candidate_left;best_right<=candidate_right;
      best_top<=candidate_top;best_bottom<=candidate_bottom;
     end
     if(!union_found)begin union_found<=1;
      uni_min_col<=min_col;uni_max_col<=max_col;uni_min_row<=min_row;uni_max_row<=max_row;
      uni_pixel_min_x<=pixel_min_x;uni_pixel_max_x<=pixel_max_x;uni_pixel_min_y<=pixel_min_y;uni_pixel_max_y<=pixel_max_y;
     end else begin
      if(min_col<uni_min_col)uni_min_col<=min_col;
      if(max_col>uni_max_col)uni_max_col<=max_col;
      if(min_row<uni_min_row)uni_min_row<=min_row;
      if(max_row>uni_max_row)uni_max_row<=max_row;
      if(pixel_min_x<uni_pixel_min_x)uni_pixel_min_x<=pixel_min_x;
      if(pixel_max_x>uni_pixel_max_x)uni_pixel_max_x<=pixel_max_x;
      if(pixel_min_y<uni_pixel_min_y)uni_pixel_min_y<=pixel_min_y;
      if(pixel_max_y>uni_pixel_max_y)uni_pixel_max_y<=pixel_max_y;
     end
    end
    scan<=scan_next;if(scan_row_end)begin scan_col<=zone_left[10:5];scan_row<=scan_row+1'b1;end else scan_col<=scan_col+1'b1;state<=last_scan?6:1;
   end
   6:begin
    O_result_valid<=1;O_candidate_valid<=union_found&&!O_scene_change;O_result_frame_id<=analysis_id;
    O_left<=union_left<zone_left?zone_left:union_left;O_right<=union_right>zone_right?zone_right:union_right;
    O_top<=union_top<zone_top?zone_top:union_top;O_bottom<=union_bottom>zone_bottom?zone_bottom:union_bottom;O_area<=best_area;
    O_analysis_count<=O_analysis_count+1'b1;state<=0;
   end
   default:;
  endcase
 end
end
endmodule
