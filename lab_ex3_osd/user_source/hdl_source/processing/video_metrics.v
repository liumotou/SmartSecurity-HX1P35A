`timescale 1ns/1ps
module video_metrics #(
 parameter integer CLOCK_HZ=75000000,
 parameter integer WINDOW_LOG2=6
)(
 input wire I_clk,I_rst_n,I_sof,I_frame_valid,
 input wire [31:0] I_frame_id,
 input wire I_latency_valid,
 input wire [31:0] I_latency_ms,
 output reg O_stats_valid,
 output reg [31:0] O_latency_min,O_latency_avg,O_latency_max,
 output reg [9:0] O_display_fps,O_new_fps,
 output reg [31:0] O_repeat_count
);
localparam integer SAMPLE_COUNT_WIDTH=(WINDOW_LOG2>0)?WINDOW_LOG2:1;
localparam integer SUM_WIDTH=32+WINDOW_LOG2;
localparam integer SECOND_COUNT_WIDTH=(CLOCK_HZ>1)?$clog2(CLOCK_HZ):1;
localparam [SAMPLE_COUNT_WIDTH-1:0] LAST_SAMPLE=(1<<WINDOW_LOG2)-1;

reg latency_valid_d;
reg [SAMPLE_COUNT_WIDTH-1:0] sample_count;
reg [SUM_WIDTH-1:0] latency_sum;
reg [31:0] block_min,block_max;
wire [SUM_WIDTH-1:0] sum_with_sample=latency_sum+{{WINDOW_LOG2{1'b0}},I_latency_ms};

reg [SECOND_COUNT_WIDTH-1:0] second_count;
reg [9:0] display_count,new_count;
reg have_frame_id;
reg [31:0] last_frame_id;
wire new_frame=I_sof&&I_frame_valid&&(!have_frame_id||(I_frame_id!=last_frame_id));
wire repeated_frame=I_sof&&I_frame_valid&&have_frame_id&&(I_frame_id==last_frame_id);
wire [9:0] display_with_sof=(I_sof&&(display_count!=10'd1023))?display_count+10'd1:display_count;
wire [9:0] new_with_sof=(new_frame&&(new_count!=10'd1023))?new_count+10'd1:new_count;

// I_latency_valid is a completion level, not a pulse. Track it even on SOF:
// an old high level at SOF must not become an invented rising edge afterward.
always @(posedge I_clk or negedge I_rst_n) begin
 if(!I_rst_n) begin
  latency_valid_d<=0; sample_count<=0; latency_sum<=0; block_min<=0; block_max<=0;
  O_stats_valid<=0; O_latency_min<=0; O_latency_avg<=0; O_latency_max<=0;
 end else begin
  latency_valid_d<=I_latency_valid;
  if(!I_sof&&I_latency_valid&&!latency_valid_d) begin
   if(sample_count==LAST_SAMPLE) begin
    O_latency_min<=(sample_count==0||I_latency_ms<block_min)?I_latency_ms:block_min;
    O_latency_avg<=sum_with_sample>>WINDOW_LOG2;
    O_latency_max<=(sample_count==0||I_latency_ms>block_max)?I_latency_ms:block_max;
    O_stats_valid<=1;
    sample_count<=0; latency_sum<=0; block_min<=0; block_max<=0;
   end else begin
    sample_count<=sample_count+1'b1;
    latency_sum<=sum_with_sample;
    if(sample_count==0||I_latency_ms<block_min) block_min<=I_latency_ms;
    if(sample_count==0||I_latency_ms>block_max) block_max<=I_latency_ms;
   end
  end
 end
end

// The closing clock, including any SOF on it, belongs to the completed window.
// Invalid SOFs still display, but do not change valid-ID history or repeats.
always @(posedge I_clk or negedge I_rst_n) begin
 if(!I_rst_n) begin
  second_count<=0; display_count<=0; new_count<=0;
  have_frame_id<=0; last_frame_id<=0;
  O_display_fps<=0; O_new_fps<=0; O_repeat_count<=0;
 end else begin
  if(second_count==CLOCK_HZ-1) begin
   second_count<=0; display_count<=0; new_count<=0;
   O_display_fps<=display_with_sof;
   O_new_fps<=new_with_sof;
  end else begin
   second_count<=second_count+1'b1;
   display_count<=display_with_sof;
   new_count<=new_with_sof;
  end
  if(I_sof&&I_frame_valid) begin
   have_frame_id<=1;
   last_frame_id<=I_frame_id;
  end
  if(repeated_frame) O_repeat_count<=O_repeat_count+32'd1;
 end
end
endmodule
