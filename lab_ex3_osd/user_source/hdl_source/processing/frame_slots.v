`timescale 1ns/1ps
// DDR-domain ownership. Publish only after all accepted writes reach the MC.
module frame_slots #(parameter integer FRAME_WORDS=172800)(
 input wire I_clk,I_rst_n,I_allocate,input wire[31:0] I_frame_id,input wire[47:0] I_tick,
 input wire I_issue,I_commit,input wire[1:0] I_commit_slot,
 input wire I_close_good,I_close_bad,I_lock,
 output reg O_grant,output reg[1:0] O_write_slot,
 output reg O_display_valid,output reg[1:0] O_read_slot,
 output reg[31:0] O_display_id,output reg[47:0] O_display_tick);
// 0 free, 1 capture, 2 complete, 3 displayed, 4 bad/draining.
reg[2:0] state[0:3];reg closed[0:3];reg[17:0] issued[0:3],committed[0:3];
reg[31:0] ids[0:3];reg[47:0] ticks[0:3];
integer i,free_slot,best;
// Bit 31 identifies the source; only the monotonic 31-bit sequence orders frames.
function newer;input[31:0] a,b;reg signed[30:0] difference;begin
 difference=a[30:0]-b[30:0];newer=difference>0;end endfunction
wire[3:0] ready={state[3]==2,state[2]==2,state[1]==2,state[0]==2};
// Parallel comparisons avoid cascading selected-ID muxes and subtractors.
wire n10=newer(ids[1],ids[0]),n20=newer(ids[2],ids[0]),n30=newer(ids[3],ids[0]);
wire n21=newer(ids[2],ids[1]),n31=newer(ids[3],ids[1]),n32=newer(ids[3],ids[2]);
wire[3:0] newest;
assign newest[0]=ready[0]&&(!ready[1]||!n10)&&(!ready[2]||!n20)&&(!ready[3]||!n30);
assign newest[1]=ready[1]&&(!ready[0]||n10)&&(!ready[2]||!n21)&&(!ready[3]||!n31);
assign newest[2]=ready[2]&&(!ready[0]||n20)&&(!ready[1]||n21)&&(!ready[3]||!n32);
assign newest[3]=ready[3]&&(!ready[0]||n30)&&(!ready[1]||n31)&&(!ready[2]||n32);
always @* begin
 free_slot=-1;best=-1;
 for(i=0;i<4;i=i+1) begin
  if(state[i]==0&&free_slot<0) free_slot=i;
  if(newest[i])best=i;
 end
end
integer j;
always @(posedge I_clk or negedge I_rst_n) begin
 if(!I_rst_n) begin
  O_grant<=0;O_write_slot<=0;O_display_valid<=0;O_read_slot<=0;O_display_id<=0;O_display_tick<=0;
  for(j=0;j<4;j=j+1) begin state[j]<=0;closed[j]<=0;issued[j]<=0;committed[j]<=0;ids[j]<=0;ticks[j]<=0;end
 end else begin
  for(j=0;j<4;j=j+1) begin
   if(I_issue&&O_grant&&O_write_slot==j) issued[j]<=issued[j]+1'b1;
   if(I_commit&&I_commit_slot==j) committed[j]<=committed[j]+1'b1;
   if(state[j]==1&&closed[j]&&issued[j]==FRAME_WORDS&&committed[j]==issued[j]) state[j]<=2;
   if(state[j]==4&&committed[j]==issued[j]) state[j]<=0;
  end
  if(I_close_good&&O_grant) begin closed[O_write_slot]<=1;O_grant<=0;end
  if(I_close_bad&&O_grant) begin state[O_write_slot]<=4;closed[O_write_slot]<=1;O_grant<=0;end
  if(I_allocate) begin
   // A short preceding frame must never become a complete frame.
   if(O_grant) begin state[O_write_slot]<=4;closed[O_write_slot]<=1;end
   O_grant<=free_slot>=0;
   if(free_slot>=0) begin
    O_write_slot<=free_slot;state[free_slot]<=1;closed[free_slot]<=0;
    issued[free_slot]<=0;committed[free_slot]<=0;ids[free_slot]<=I_frame_id;ticks[free_slot]<=I_tick;
   end
  end
  // Caller asserts lock only after old read responses have drained.
  if(I_lock&&best>=0) begin
   if(O_display_valid) state[O_read_slot]<=0;
   for(j=0;j<4;j=j+1) if(state[j]==2&&j!=best) state[j]<=0;
   state[best]<=3;O_read_slot<=best;O_display_valid<=1;O_display_id<=ids[best];O_display_tick<=ticks[best];
  end
 end
end
endmodule
