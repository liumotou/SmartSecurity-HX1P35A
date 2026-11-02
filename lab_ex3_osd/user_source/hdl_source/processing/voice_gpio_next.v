`timescale 1ns/1ps
module voice_gpio_next #(
 parameter integer MIN_HIGH_CYCLES=150000,
 parameter integer MIN_LOW_CYCLES=1500000,
 parameter integer HOLDOFF_CYCLES=37500000
)(input wire I_clk,I_rst_n,I_gpio,output reg O_next);
// 75MHz defaults: qualify high 2ms, qualify low 20ms, lock out 500ms.
// A high already present at reset is ignored until a real stable low is seen.
localparam HW=MIN_HIGH_CYCLES<2?1:$clog2(MIN_HIGH_CYCLES+1);
localparam LW=MIN_LOW_CYCLES<2?1:$clog2(MIN_LOW_CYCLES+1);
localparam CW=HOLDOFF_CYCLES<2?1:$clog2(HOLDOFF_CYCLES+1);
(* async_reg="true" *) reg[2:0] gpio_sync;
reg[2:0] settled;
reg[HW-1:0] high_count;
reg[LW-1:0] low_count;
reg[CW-1:0] cooldown;
reg armed;
always @(posedge I_clk or negedge I_rst_n) begin
 if(!I_rst_n)begin gpio_sync<=0;settled<=0;end
 else begin gpio_sync<={gpio_sync[1:0],I_gpio};settled<={settled[1:0],1'b1};end
end
always @(posedge I_clk or negedge I_rst_n) begin
 if(!I_rst_n)begin O_next<=0;high_count<=0;low_count<=0;cooldown<=0;armed<=0;end
 else begin
  O_next<=0;
  if(cooldown!=0)cooldown<=cooldown-1'b1;
  if(!settled[2])begin high_count<=0;low_count<=0;armed<=0;end
  else if(!gpio_sync[2])begin
   high_count<=0;
   if(low_count<MIN_LOW_CYCLES)low_count<=low_count+1'b1;
   if(low_count==MIN_LOW_CYCLES-1)armed<=1;
  end else begin
   low_count<=0;
   if(armed)begin
    if(high_count==MIN_HIGH_CYCLES-1)begin
     high_count<=0;armed<=0;
     // Consume ignored pulses too: never emit later during a held high.
     if(cooldown==0)begin O_next<=1;cooldown<=HOLDOFF_CYCLES-1;end
    end else high_count<=high_count+1'b1;
   end else high_count<=0;
  end
 end
end
endmodule
