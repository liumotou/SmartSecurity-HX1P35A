`timescale 1ns/1ps
// Centered 3x3 Sobel. ALL paths are delayed one raster line + one pixel,
// then three arithmetic stages; RGB/DE/HS/VS/coordinates share that delay.
module sobel_stream #(parameter WIDTH=1280,HEIGHT=720,H_TOTAL=1650)(
 input wire I_clk,I_rst_n,input wire[23:0] I_rgb,input wire I_de,I_hs,I_vs,I_sof,I_eol,
 input wire[10:0] I_x,input wire[9:0] I_y,input wire[31:0] I_frame_id,input wire I_frame_valid,
 output wire[23:0] O_rgb,output wire O_de,O_hs,O_vs,O_sof,O_eol,
 output wire[10:0] O_x,output wire[9:0] O_y,output wire[31:0] O_frame_id,output wire O_frame_valid,
 output reg[7:0] O_edge);
localparam DELAY=H_TOTAL+1;
localparam RASTER_ADDR_WIDTH=$clog2(DELAY),COLUMN_ADDR_WIDTH=$clog2(WIDTH);
// Production contract: a valid frame starts at SOF and retains its 32-bit ID.
// Share that ID, but keep all per-clock payload/control fields in the raster RAM.
// Keep the BRAM read synchronous and unconditional. Reconstruct the full packet
// at the original pipe0 stage; an entry stays live through that tag consumption.
localparam ID_HOLD_CYCLES=DELAY+1,ID_HOLD_WIDTH=$clog2(DELAY+2);
reg[31:0] frame_ids[0:3];reg[3:0] id_initialized;
reg[ID_HOLD_WIDTH-1:0] id_hold[0:3];
reg[1:0] active_id,next_id;reg frame_locked,id_available;
wire[3:0] matching_ids,free_ids;
genvar id_slot;
generate for(id_slot=0;id_slot<4;id_slot=id_slot+1)begin: id_status
 assign matching_ids[id_slot]=id_initialized[id_slot]&&frame_ids[id_slot]==I_frame_id;
 assign free_ids[id_slot]=id_hold[id_slot]==0;
end endgenerate
integer id_search,id_update;
always @* begin
 next_id=0;id_available=(|matching_ids)||(|free_ids);
 for(id_search=0;id_search<4;id_search=id_search+1)
  if(matching_ids[id_search])next_id=id_search;
 if(!(|matching_ids))for(id_search=0;id_search<4;id_search=id_search+1)
  if(free_ids[id_search])next_id=id_search;
end
wire[1:0] packet_id=I_sof?next_id:active_id;
wire packet_valid=I_frame_valid&&(I_sof?id_available:
 (frame_locked&&I_frame_id==frame_ids[active_id]));
wire[52:0] packet={packet_valid,packet_id,I_x,I_y,I_de,I_hs,I_vs,I_sof,I_eol,I_rgb};
(* ram_style="bram" *) reg[52:0] raster_delay[0:DELAY-1];
reg[52:0] delayed_compact;reg[82:0] pipe0,pipe1,pipe2;
reg[RASTER_ADDR_WIDTH-1:0] pointer;reg filled;reg[3:0] valid_pipe;
wire[15:0] gray_sum=I_rgb[23:16]*16'd77+I_rgb[15:8]*16'd150+I_rgb[7:0]*16'd29;
(* ram_style="bram" *) reg[7:0] line1[0:WIDTH-1],line2[0:WIDTH-1];
reg[7:0] read_a,read_b,bot_read,t0,t1,m0,m1,b0,b1;reg parity_d;
wire[7:0] top_read=parity_d?read_b:read_a,mid_read=parity_d?read_a:read_b;
wire[COLUMN_ADDR_WIDTH-1:0] column=I_x[COLUMN_ADDR_WIDTH-1:0];
reg de_d;reg[10:0] x_d;reg[9:0] y_d;reg signed[11:0] gx,gy;reg[12:0] energy;
wire[11:0] ax=gx[11]?-gx:gx,ay=gy[11]?-gy:gy;
assign {O_frame_valid,O_frame_id,O_x,O_y,O_de,O_hs,O_vs,O_sof,O_eol,O_rgb}=
 valid_pipe[3]?pipe2:83'd0;
always @(posedge I_clk) begin
 if(I_rst_n) begin
  raster_delay[pointer]<=packet;
  delayed_compact<=raster_delay[pointer];
  if(I_de&&I_x<WIDTH) begin
   read_a<=line1[column];read_b<=line2[column];parity_d<=I_y[0];bot_read<=gray_sum[15:8];
   // Alternate whole line banks: synchronous read-before-write, no RAM-to-RAM copy.
   if(I_y[0])line2[column]<=gray_sum[15:8];else line1[column]<=gray_sum[15:8];
  end
 end
end
always @(posedge I_clk or negedge I_rst_n) begin
 if(!I_rst_n) begin pointer<=0;filled<=0;valid_pipe<=0;pipe0<=0;pipe1<=0;pipe2<=0;
  active_id<=0;frame_locked<=0;id_initialized<=0;
  for(id_update=0;id_update<4;id_update=id_update+1)begin frame_ids[id_update]<=0;id_hold[id_update]<=0;end
  de_d<=0;x_d<=0;y_d<=0;t0<=0;t1<=0;m0<=0;m1<=0;b0<=0;b1<=0;gx<=0;gy<=0;energy<=0;O_edge<=0;
 end else begin
  // Hold each entry through the last tag consumed by pipe0. A countdown of one is
  // still busy: reuse on the following cycle is deliberately conservative.
  for(id_update=0;id_update<4;id_update=id_update+1)
   if(id_hold[id_update]!=0)id_hold[id_update]<=id_hold[id_update]-1'b1;
  if(packet_valid)id_hold[packet_id]<=ID_HOLD_CYCLES;
  if(I_sof)begin
   frame_locked<=packet_valid;
   if(packet_valid)begin active_id<=next_id;frame_ids[next_id]<=I_frame_id;id_initialized[next_id]<=1;end
  end else if(I_frame_valid&&I_frame_id!=frame_ids[active_id])frame_locked<=0;
  // Malformed ID changes or table exhaustion invalidate only new packets;
  // older valid frame tails drain unchanged. Recovery requires a valid SOF.
  if(pointer==DELAY-1)begin pointer<=0;filled<=1;end else pointer<=pointer+1'b1;
  valid_pipe<={valid_pipe[2:0],filled};
  pipe0<={delayed_compact[52],frame_ids[delayed_compact[51:50]],delayed_compact[49:0]};
  pipe1<=pipe0;pipe2<=pipe1;
  de_d<=I_de;x_d<=I_x;y_d<=I_y;
  gx<=0;gy<=0;
  if(de_d) begin
   if(x_d==0)begin t0<=0;t1<=top_read;m0<=0;m1<=mid_read;b0<=0;b1<=bot_read;end
   else begin t0<=t1;t1<=top_read;m0<=m1;m1<=mid_read;b0<=b1;b1<=bot_read;end
   if(x_d>=2&&y_d>=2)begin
    gx<=$signed({4'b0,top_read})+($signed({4'b0,mid_read})<<<1)+$signed({4'b0,bot_read})-
        $signed({4'b0,t0})-($signed({4'b0,m0})<<<1)-$signed({4'b0,b0});
    gy<=$signed({4'b0,b0})+($signed({4'b0,b1})<<<1)+$signed({4'b0,bot_read})-
        $signed({4'b0,t0})-($signed({4'b0,t1})<<<1)-$signed({4'b0,top_read});
   end
  end
  energy<={1'b0,ax}+{1'b0,ay};
  // pipe1 becomes pipe2 after this edge; use its centered coordinates here.
  if(valid_pipe[2]&&pipe1[28]&&pipe1[49:39]>0&&pipe1[49:39]<WIDTH-1&&
     pipe1[38:29]>0&&pipe1[38:29]<HEIGHT-1)
   O_edge<=energy>255?8'd255:energy[7:0];
  else O_edge<=0;
 end
end
endmodule
