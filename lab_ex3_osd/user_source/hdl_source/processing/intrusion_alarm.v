`timescale 1ns/1ps
// Count unique analysis results. Acquisition stalls preserve a latched alarm.
module intrusion_alarm #(
 parameter CONFIRM_FRAMES=8,HOLD_FRAMES=400,MIN_AREA=6,STRONG_MIN=32,
 parameter ARM_FILTER_CYCLES=1500000,BEEP_DIV=9375000,CARRIER_DIV=13750
)(
 input wire I_clk,I_rst_n,I_arm,I_result,input wire[31:0] I_result_id,
 input wire I_clear,I_candidate,I_scene,input wire[9:0] I_area,input wire[13:0] I_strong,
 output reg O_alarm,output wire O_buzzer_n,O_led,output wire O_armed);
localparam ARM_W=ARM_FILTER_CYCLES<2?1:$clog2(ARM_FILTER_CYCLES+1);
(* async_reg="true" *)reg[2:0] arm_sync;
reg[ARM_W-1:0] arm_count;reg armed;
assign O_armed=armed;
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin arm_sync<=0;arm_count<=0;armed<=0;end
 else begin
  arm_sync<={arm_sync[1:0],I_arm};
  if(arm_sync[2]==armed)arm_count<=0;
  else if(ARM_FILTER_CYCLES<2||arm_count==ARM_FILTER_CYCLES-1)begin armed<=arm_sync[2];arm_count<=0;end
  else arm_count<=arm_count+1'b1;
 end
end
reg[3:0] confirm_count;reg[8:0] miss_count;reg seen;reg[31:0] seen_id;
wire tick=I_result&&(!seen||I_result_id!=seen_id);
wire motion_ok=I_candidate&&!I_scene&&I_area>=MIN_AREA&&I_strong>=STRONG_MIN;
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin confirm_count<=0;miss_count<=0;O_alarm<=0;seen<=0;seen_id<=0;end
 else if(I_clear||!armed)begin confirm_count<=0;miss_count<=0;O_alarm<=0;seen<=0;end
 else if(tick)begin
  seen<=1;seen_id<=I_result_id;
  if(!O_alarm)begin
   if(motion_ok)begin
    if(confirm_count==CONFIRM_FRAMES-1)begin O_alarm<=1;miss_count<=0;end
    else confirm_count<=confirm_count+1'b1;
   end else confirm_count<=0;
  end else if(motion_ok)miss_count<=0;
  else if(miss_count==HOLD_FRAMES-1)begin O_alarm<=0;confirm_count<=0;miss_count<=0;end
  else miss_count<=miss_count+1'b1;
 end
end
localparam BW=BEEP_DIV<2?1:$clog2(BEEP_DIV);
localparam CW=CARRIER_DIV<2?1:$clog2(CARRIER_DIV);
reg[BW-1:0] beep_count;reg[CW-1:0] carrier_count;reg beep_phase,carrier;
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin beep_count<=0;carrier_count<=0;beep_phase<=0;carrier<=0;end
 else if(!O_alarm)begin beep_count<=0;carrier_count<=0;beep_phase<=0;carrier<=0;end
 else begin
  if(beep_count==BEEP_DIV-1)begin beep_count<=0;beep_phase<=!beep_phase;end else beep_count<=beep_count+1'b1;
  if(carrier_count==CARRIER_DIV-1)begin carrier_count<=0;carrier<=!carrier;end else carrier_count<=carrier_count+1'b1;
 end
end
assign O_buzzer_n=~(O_alarm&&beep_phase&&(CARRIER_DIV<2||carrier));
assign O_led=O_alarm&&beep_phase;
endmodule
