`timescale 1ns/1ps
module button_events #(parameter integer DEBOUNCE_CYCLES=750000,
 parameter integer LONG_CYCLES=75000000)(
 input wire I_clk,I_rst_n,I_key_n,output reg O_short,O_long);
reg [1:0] sync;reg stable;reg [31:0] debounce,held;reg fired;
wire released=sync[1]&&!stable&&debounce==DEBOUNCE_CYCLES-1;
always @(posedge I_clk or negedge I_rst_n) begin
 if(!I_rst_n) begin sync<=2'b11;stable<=1;debounce<=0;held<=0;fired<=0;O_short<=0;O_long<=0;end
 else begin
  sync<={sync[0],I_key_n};O_short<=0;O_long<=0;
  if(sync[1]==stable) debounce<=0;
  else if(debounce==DEBOUNCE_CYCLES-1) begin
   stable<=sync[1];debounce<=0;
   if(sync[1]) begin O_short<=!fired;held<=0;fired<=0;end
   else begin held<=0;fired<=0;end
  end else debounce<=debounce+1;
  // Release wins at the threshold; a single press emits exactly one event.
  if(!stable&&!fired&&!released) begin
   if(held==LONG_CYCLES-1) begin fired<=1;O_long<=1;end
   else held<=held+1;
  end
 end
end
endmodule
