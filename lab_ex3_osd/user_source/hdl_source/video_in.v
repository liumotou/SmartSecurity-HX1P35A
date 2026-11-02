`timescale 1ns/1ps
module video_in #(parameter integer FRAME_WORDS=172800,FRAME_LINES=720)(
 input wire I_rst_n,I_camera_clk,I_camera_frame_start,I_camera_valid,I_camera_last,
 input wire[127:0] I_camera_data,input wire I_mipi_rx_error,I_ddr_clk,
 input wire I_display_pause,I_video_out_rd_busy,output wire O_video_in_wr_busy,
 output wire[1:0] O_video_out_rp,
 output reg O_ddr_user_wr_en,output reg[24:0] O_ddr_user_addr,
 output wire[127:0] O_ddr_user_wr_data,input wire I_ddr_user_ready,
 input wire[31:0] I_capture_id,input wire[47:0] I_capture_tick,
 input wire I_mc_write_commit,input wire[24:0] I_mc_write_addr,input wire I_display_lock,
 output wire O_display_valid,output wire[31:0] O_display_id,output wire[47:0] O_display_tick,
 output reg[31:0] O_drop_count);
reg[4:0] head_reset;reg[7:0] valid_delay;reg[127:0] data_delay[0:7];
reg camera_bad,camera_done;reg[17:0] camera_words;reg[9:0] camera_line;
reg[17:0] camera_line_words;wire full,empty;wire[8:0] available;
wire fifo_reset=!I_rst_n|(|head_reset);
integer i;
always @(posedge I_camera_clk or negedge I_rst_n) begin
 if(!I_rst_n) begin head_reset<=0;valid_delay<=0;camera_bad<=0;camera_words<=0;camera_done<=0;camera_line<=0;camera_line_words<=0;
  for(i=0;i<8;i=i+1)data_delay[i]<=0;
 end else begin
  head_reset<={head_reset[3:0],I_camera_frame_start};
  valid_delay<={valid_delay[6:0],I_camera_valid};
  data_delay[0]<=I_camera_data;for(i=1;i<8;i=i+1)data_delay[i]<=data_delay[i-1];
  if(I_camera_frame_start) begin camera_words<=I_camera_valid?1:0;camera_bad<=0;camera_done<=0;camera_line<=0;camera_line_words<=I_camera_valid?1:0;end
  else if(I_camera_valid) begin
   if(camera_words<FRAME_WORDS) camera_words<=camera_words+1'b1;
   else camera_bad<=1;
  end
  if(!I_camera_frame_start&&I_camera_valid)begin
   camera_line_words<=camera_line_words+1'b1;
   if(I_camera_last)begin
    camera_line_words<=0;camera_line<=camera_line+1'b1;
    if(camera_line_words!=FRAME_WORDS/FRAME_LINES-1)camera_bad<=1;
    if(camera_line==FRAME_LINES-1)begin
     if(camera_words==FRAME_WORDS-1)camera_done<=1;else camera_bad<=1;
    end
   end
  end
  if(I_mipi_rx_error||(valid_delay[7]&&full&&!fifo_reset)) camera_bad<=1;
 end
end
wire frame_start;wire[79:0] capture_meta;wire mailbox_busy;
cdc_mailbox #(.WIDTH(80)) frame_mailbox(I_camera_clk,I_ddr_clk,I_rst_n,
 I_camera_frame_start,{I_capture_id,I_capture_tick},mailbox_busy,frame_start,capture_meta);
reg[1:0] bad_sync,done_sync;reg[17:0] sent;reg burst;reg[7:0] burst_count;reg frame_open;
wire grant;wire[1:0] write_slot;
wire close_good=grant&&frame_open&&(sent==FRAME_WORDS)&&done_sync[1]&&!bad_sync[1];
wire close_bad=grant&&frame_open&&bad_sync[1];
wire[1:0] commit_slot=I_mc_write_addr>=25'd21000000 ? 2'd3 : 
 I_mc_write_addr>=25'd14000000 ? 2'd2 : I_mc_write_addr>=25'd7000000 ? 2'd1 : 2'd0;
frame_slots #(.FRAME_WORDS(FRAME_WORDS)) slots(.I_clk(I_ddr_clk),.I_rst_n(I_rst_n),
 .I_allocate(frame_start&&!I_display_pause),.I_frame_id(capture_meta[79:48]),.I_tick(capture_meta[47:0]),
 .I_issue(O_ddr_user_wr_en),.I_commit(I_mc_write_commit),.I_commit_slot(commit_slot),
 .I_close_good(close_good),.I_close_bad(close_bad),.I_lock(I_display_lock),
 .O_grant(grant),.O_write_slot(write_slot),.O_display_valid(O_display_valid),.O_read_slot(O_video_out_rp),
 .O_display_id(O_display_id),.O_display_tick(O_display_tick));
wire pop=burst&&I_ddr_user_ready&&!empty&&!bad_sync[1]&&frame_open&&sent<FRAME_WORDS&&!frame_start;
assign O_video_in_wr_busy=burst|O_ddr_user_wr_en;
w128_d512_fifo fifo(.rst(fifo_reset),.clkw(I_camera_clk),.clkr(I_ddr_clk),
 .we(valid_delay[7]&&!fifo_reset&&!camera_bad),.di(data_delay[7]),.re(pop),
 .dout(O_ddr_user_wr_data),.rdusedw(available),.empty_flag(empty),.full_flag(full),
 .valid(),.afull(),.aempty(),.wrusedw());
reg allocate_d;
always @(posedge I_ddr_clk or negedge I_rst_n) begin
 if(!I_rst_n) begin bad_sync<=0;done_sync<=0;sent<=0;burst<=0;burst_count<=0;frame_open<=0;
  O_ddr_user_wr_en<=0;O_ddr_user_addr<=0;O_drop_count<=0;allocate_d<=0;
 end else begin
  bad_sync<={bad_sync[0],camera_bad};done_sync<={done_sync[0],camera_done};allocate_d<=frame_start;O_ddr_user_wr_en<=pop;
  if(O_ddr_user_wr_en) O_ddr_user_addr<=O_ddr_user_addr+25'd8;
  if(allocate_d&&grant) begin
   case(write_slot) 0:O_ddr_user_addr<=0;1:O_ddr_user_addr<=7000000;
    2:O_ddr_user_addr<=14000000;3:O_ddr_user_addr<=21000000;endcase
   frame_open<=1;
  end
  if(allocate_d&&!grant)O_drop_count<=O_drop_count+1'b1;
  if(frame_start) begin
   if(frame_open&&sent!=FRAME_WORDS) O_drop_count<=O_drop_count+1'b1;
   sent<=0;burst<=0;burst_count<=0;frame_open<=0;
  end else if(close_bad||close_good) begin
   frame_open<=0;burst<=0;if(close_bad) O_drop_count<=O_drop_count+1'b1;
  end else begin
   if(pop) begin sent<=sent+1'b1;
    if(burst_count==239) begin burst<=0;burst_count<=0;end else burst_count<=burst_count+1'b1;
   end
   if(!burst&&frame_open&&grant&&!I_video_out_rd_busy&&available>=240&&sent<FRAME_WORDS) begin burst<=1;burst_count<=0;end
  end
 end
end
endmodule

